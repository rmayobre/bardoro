// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../audio/cancel_token.dart';
import '../voice/voice_settings.dart';
import 'tts_engine.dart';

/// `POST {baseUrl}/v1/audio/speech` with the Kokoro-FastAPI JSON contract. Same behaviour as `synthesize()`:
/// 900 s per request, 3 attempts, waiting 3 s x attempt between them, success only for status 200 with a
/// non-empty body, and an immediate stop when the error says the voice is not found / invalid.
class KokoroHttpClient {
  KokoroHttpClient(
    String baseUrl, {
    http.Client? client,
    this.timeout = const Duration(seconds: 900),
    this.delay = _sleep,
  }) : base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _http = client ?? http.Client();

  final String base;
  final Duration timeout;

  /// Injected so tests do not really wait 3 s and 6 s.
  final Future<void> Function(Duration) delay;
  final http.Client _http;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  /// [onLog] gets lines without the chunk label; the caller prefixes it.
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    required num speed,
    int retries = 3,
    CancelToken? cancel,
    void Function(String message)? onLog,
  }) async {
    final uri = Uri.parse('$base/v1/audio/speech');
    final body = jsonEncode({
      'model': 'kokoro',
      'input': text,
      'voice': voice,
      'response_format': 'flac',
      'speed': speed,
    });
    for (var attempt = 1; attempt <= retries; attempt++) {
      if (cancel?.isCancelled ?? false) throw const CancelledException();
      String err;
      try {
        final request = _http
            .post(
              uri,
              headers: {'content-type': 'application/json'},
              body: body,
            )
            .timeout(timeout);
        // package:http cannot abort a request in flight, so stop waiting for it instead.
        final aborted = Completer<http.Response>();
        final stop = cancel?.onCancel(() {
          if (!aborted.isCompleted) {
            aborted.completeError(const CancelledException());
          }
        });
        final http.Response r;
        try {
          r = await Future.any([request, aborted.future]);
        } finally {
          stop?.call();
          unawaited(
            request.then<void>((_) {}, onError: (_) {}),
          ); // abandoned request: discard its result
        }
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
        err =
            'HTTP ${r.statusCode}: ${_clip(utf8.decode(r.bodyBytes, allowMalformed: true), 300)}';
      } on CancelledException {
        rethrow;
      } on TimeoutException {
        err = 'timed out after ${timeout.inSeconds}s';
      } on Exception catch (e) {
        err = '$e';
      }
      if (cancel?.isCancelled ?? false) throw const CancelledException();
      onLog?.call('attempt $attempt/$retries failed: $err');
      if (_isVoiceError(err)) throw KokoroVoiceRejected(err);
      if (attempt < retries) {
        onLog?.call('retrying in ${3 * attempt}s');
        await delay(Duration(seconds: 3 * attempt));
      }
    }
    onLog?.call('giving up after $retries attempts');
    throw KokoroUnavailable('Giving up on a chunk after repeated failures.');
  }

  /// `GET /v1/audio/voices`: the "Test connection" check. Not used by the pipeline.
  Future<List<String>> listVoices() async {
    final r = await _http
        .get(Uri.parse('$base/v1/audio/voices'))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw KokoroUnavailable('HTTP ${r.statusCode} from $base');
    }
    final data = jsonDecode(r.body);
    final v = data is Map ? data['voices'] : data;
    return v is List ? [for (final e in v) '$e'] : const [];
  }

  void close() => _http.close();

  static bool _isVoiceError(String err) {
    final low = err.toLowerCase();
    return low.contains('voice') &&
        (low.contains('not found') || low.contains('invalid'));
  }

  static String _clip(String s, int n) => s.length <= n ? s : s.substring(0, n);
}

class KokoroHttpEngine implements TtsEngine {
  KokoroHttpEngine(
    this.baseUrl, {
    http.Client? client,
    Duration? timeout,
    Future<void> Function(Duration)? delay,
  }) : _client = KokoroHttpClient(
         baseUrl,
         client: client,
         timeout: timeout ?? const Duration(seconds: 900),
         delay: delay ?? KokoroHttpClient._sleep,
       );

  /// Never hardcoded: it comes from `$KOKORO_URL`, `--url` or the app's settings.
  final String baseUrl;
  final KokoroHttpClient _client;

  @override
  String get id => 'kokoro-http';

  @override
  Map<String, Object?> get settingsExtras => const {};

  @override
  Set<String> get unresolvedWords => const {};

  /// No network call here (the CLI does not probe the server either); use [testConnection] for that.
  @override
  Future<void> prepare() async {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw TtsException(
        '"$baseUrl" is not a valid Kokoro server URL.',
        hint: 'Use something like https://your-kokoro-server',
      );
    }
  }

  Future<List<String>> testConnection() => _client.listVoices();

  @override
  Future<void> synthesizeToFile({
    required String text,
    required VoiceSettings voice,
    required File dest,
    CancelToken? cancel,
    void Function(String message)? onLog,
  }) async {
    final bytes = await _client.synthesize(
      text: text,
      voice: voice.voice,
      speed: voice.speed,
      cancel: cancel,
      onLog: onLog,
    );
    final part = File('${dest.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(dest.path);
  }

  @override
  Future<void> dispose() async => _client.close();
}
