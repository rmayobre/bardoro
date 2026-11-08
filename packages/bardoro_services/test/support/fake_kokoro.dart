// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

/// A stand-in for Kokoro-FastAPI (port of tests/fake_kokoro_server.py): answers POST /v1/audio/speech with a
/// short FLAC tone whose length depends on the text, and records every request.
class FakeKokoro {
  FakeKokoro._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> requests = [];

  /// If set, called for each request first; return a status code to short-circuit (e.g. 500), else null.
  int? Function(int requestNumber, Map<String, dynamic> body)? failWith;
  String failBody = 'boom';

  /// Called after the n-th successful response (1-based), e.g. to cancel a run mid-way.
  void Function(int n)? afterResponse;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<FakeKokoro> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeKokoro._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest req) async {
    if (req.method == 'GET' && req.uri.path == '/v1/audio/voices') {
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'voices': ['am_onyx', 'am_adam'],
          }),
        );
      await req.response.close();
      return;
    }
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    requests.add(body);
    final n = requests.length;
    final status = failWith?.call(n, body);
    if (status != null) {
      req.response
        ..statusCode = status
        ..write(failBody);
      await req.response.close();
      return;
    }
    final seconds = ((body['input'] as String).length / 400).clamp(0.3, 3.0);
    final audio = await _tone(seconds);
    req.response
      ..headers.contentType = ContentType('audio', 'flac')
      ..contentLength = audio.length
      ..add(audio);
    await req.response.close();
    afterResponse?.call(n);
  }

  static final Map<double, List<int>> _cache = {};

  static Future<List<int>> _tone(double seconds) async {
    final key = (seconds * 10).roundToDouble();
    return _cache[key] ??= await _generate(key / 10);
  }

  static Future<List<int>> _generate(double seconds) async {
    final r = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=220:duration=$seconds',
      '-ar',
      '24000',
      '-f',
      'flac',
      '-',
    ], stdoutEncoding: null);
    if (r.exitCode != 0) throw StateError('ffmpeg failed: ${r.stderr}');
    return r.stdout as List<int>;
  }

  /// The `input` texts, in order.
  List<String> get inputs => [for (final r in requests) r['input'] as String];

  Future<void> close() => _server.close(force: true);
}
