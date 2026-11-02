// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_kokoro.dart';

void main() {
  late FakeKokoro server;
  late Directory tmp;
  final waits = <Duration>[];
  Future<void> noWait(Duration d) async => waits.add(d);

  setUp(() async {
    server = await FakeKokoro.start();
    tmp = await Directory.systemTemp.createTemp('http_engine');
    waits.clear();
  });
  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  test(
    'sends the Kokoro-FastAPI JSON contract and writes the FLAC via .part + rename',
    () async {
      final engine = KokoroHttpEngine('${server.url}/', delay: noWait);
      final dest = File('${tmp.path}/c.flac');
      await engine.synthesizeToFile(
        text: 'Hello there.',
        voice: const VoiceSettings(),
        dest: dest,
      );
      expect(server.requests.single, {
        'model': 'kokoro',
        'input': 'Hello there.',
        'voice': 'am_onyx(4)+am_adam(1)',
        'response_format': 'flac',
        'speed': 1.0,
      });
      expect(dest.lengthSync(), greaterThan(0));
      expect(File('${dest.path}.part').existsSync(), isFalse);
      expect(String.fromCharCodes(dest.readAsBytesSync().take(4)), 'fLaC');
    },
  );

  test('retries 3 times waiting 3 s then 6 s, then gives up', () async {
    server.failWith = (n, _) => 500;
    final engine = KokoroHttpEngine(server.url, delay: noWait);
    final log = <String>[];
    await expectLater(
      engine.synthesizeToFile(
        text: 'x',
        voice: const VoiceSettings(),
        dest: File('${tmp.path}/c.flac'),
        onLog: log.add,
      ),
      throwsA(isA<KokoroUnavailable>()),
    );
    expect(server.requests.length, 3);
    expect(waits, [const Duration(seconds: 3), const Duration(seconds: 6)]);
    expect(log, [
      'attempt 1/3 failed: HTTP 500: boom',
      'retrying in 3s',
      'attempt 2/3 failed: HTTP 500: boom',
      'retrying in 6s',
      'attempt 3/3 failed: HTTP 500: boom',
      'giving up after 3 attempts',
    ]);
    expect(File('${tmp.path}/c.flac').existsSync(), isFalse);
  });

  test('succeeds on a later attempt', () async {
    server.failWith = (n, _) => n < 3 ? 503 : null;
    final engine = KokoroHttpEngine(server.url, delay: noWait);
    await engine.synthesizeToFile(
      text: 'x',
      voice: const VoiceSettings(),
      dest: File('${tmp.path}/c.flac'),
    );
    expect(server.requests.length, 3);
    expect(File('${tmp.path}/c.flac').existsSync(), isTrue);
  });

  test('a voice error aborts at once with the plain-voice hint', () async {
    server.failWith = (n, _) => 400;
    server.failBody = 'Voice am_onyx(4) not found';
    final engine = KokoroHttpEngine(server.url, delay: noWait);
    await expectLater(
      engine.synthesizeToFile(
        text: 'x',
        voice: const VoiceSettings(),
        dest: File('${tmp.path}/c.flac'),
      ),
      throwsA(
        isA<KokoroVoiceRejected>().having(
          (e) => e.hint,
          'hint',
          contains('am_onyx'),
        ),
      ),
    );
    expect(server.requests.length, 1);
    expect(waits, isEmpty);
  });

  test('a 200 with an empty body is a failure', () async {
    final mock = MockClient((_) async => http.Response('', 200));
    final engine = KokoroHttpEngine(
      'http://example.invalid',
      client: mock,
      delay: noWait,
    );
    await expectLater(
      engine.synthesizeToFile(
        text: 'x',
        voice: const VoiceSettings(),
        dest: File('${tmp.path}/c.flac'),
      ),
      throwsA(isA<KokoroUnavailable>()),
    );
  });

  test('a transport error is retried and logged', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      throw http.ClientException('connection refused');
    });
    final engine = KokoroHttpEngine(
      'http://example.invalid',
      client: mock,
      delay: noWait,
    );
    final log = <String>[];
    await expectLater(
      engine.synthesizeToFile(
        text: 'x',
        voice: const VoiceSettings(),
        dest: File('${tmp.path}/c.flac'),
        onLog: log.add,
      ),
      throwsA(isA<KokoroUnavailable>()),
    );
    expect(calls, 3);
    expect(log.first, contains('connection refused'));
  });

  test(
    'cancel stops waiting for an in-flight request',
    () async {
      final mock = MockClient(
        (_) => Future.delayed(
          const Duration(seconds: 30),
          () => http.Response('x', 200),
        ),
      );
      final engine = KokoroHttpEngine(
        'http://example.invalid',
        client: mock,
        delay: noWait,
      );
      final cancel = CancelToken();
      final run = engine.synthesizeToFile(
        text: 'x',
        voice: const VoiceSettings(),
        dest: File('${tmp.path}/c.flac'),
        cancel: cancel,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();
      await expectLater(run, throwsA(isA<CancelledException>()));
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'prepare rejects a malformed URL; testConnection lists voices',
    () async {
      await expectLater(
        KokoroHttpEngine('not a url').prepare(),
        throwsA(isA<TtsException>()),
      );
      final engine = KokoroHttpEngine(server.url);
      await engine.prepare();
      expect(await engine.testConnection(), ['am_onyx', 'am_adam']);
      expect(jsonEncode(engine.settingsExtras), '{}');
    },
  );
}
