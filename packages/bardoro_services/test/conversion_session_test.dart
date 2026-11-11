// SPDX-License-Identifier: GPL-3.0-or-later
// End to end through real volley isolates: a coroutine analyses the epub, an actor converts it against a fake
// Kokoro server. Needs ffmpeg + ffprobe.
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:volley/volley.dart';

import 'support/epub_builder.dart';
import 'support/fake_kokoro.dart';

const _dictionary = '../bardoro_core/assets/dictionary/en_words.txt';

void main() {
  late FakeKokoro server;
  late Directory tmp;
  late Workspace ws;
  late BookEntry entry;

  setUpAll(() async => Bootstrapper.initialize());
  tearDownAll(() async => Bootstrapper.shutdown());

  setUp(() async {
    server = await FakeKokoro.start();
    tmp = await Directory.systemTemp.createTemp('session');
    ws = Workspace(tmp.path);
    final epub = File(p.join(tmp.path, "The Brothers' War.epub"))
      ..writeAsBytesSync(smokeEpub());
    entry = (await LibraryService(ws).import(epub.path).run()).getOrThrow();
  });
  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  test('analysis runs in a volley coroutine and finds sections and names', () async {
    final analysis = (await const BookAnalyzer(dictionaryPath: _dictionary)
            .analyze(entry.epubPath)
            .run())
        .getOrThrow();
    expect(analysis.sections.map((s) => s.title), ['Prologue', 'Chapter 1', 'Epilogue']);
    expect(analysis.words.map((w) => w.word), containsAll(['Urza', 'Mishra']));
  });

  test('analysis failure comes back as a Result, not an exception', () async {
    final r = await const BookAnalyzer(dictionaryPath: _dictionary)
        .analyze('${tmp.path}/missing.epub')
        .run();
    expect(r.isFailure, isTrue);
  });

  test('a conversion runs in an actor isolate and streams progress', () async {
    await File(entry.project.wordsCsv).create(recursive: true);
    await File(entry.project.wordsCsv)
        .writeAsString('word,count,pronunciation\nUrza,5,Er-zuh\n');
    final request = (await JobBuilder(
      AppSettings(workspaceDir: tmp.path, kokoroUrl: server.url),
    ).build(entry, voice: const VoiceSettings()).run())
        .getOrThrow();

    final session = ConversionSession(pollInterval: const Duration(milliseconds: 50));
    final phases = <ConversionPhase>[];
    final sub = session.progress.collect().listen((s) => phases.add(s.phase));
    await session.start(request);
    await session.finished.timeout(const Duration(seconds: 60));

    final last = session.progress.value;
    expect(last.phase, ConversionPhase.finished, reason: '${last.error}\n${last.log.join('\n')}');
    expect(last.totalChapters, 3);
    expect(last.chaptersDone, 3);
    expect(last.result!.chapterMarkers, 3);
    expect(File(entry.project.m4bPath).existsSync(), isTrue);
    expect(phases, contains(ConversionPhase.combining));
    expect(server.inputs.join('\n'), contains('Er-zuh'));
    await sub.cancel();
    await session.dispose();

    final after = (await LibraryService(ws).scan().run()).single;
    expect(after.status, BookStatus.done);
  });

  test('cancel stops the worker; a second session resumes without new server calls for finished chapters', () async {
    final request = (await JobBuilder(
      AppSettings(workspaceDir: tmp.path, kokoroUrl: server.url),
    ).build(entry, voice: const VoiceSettings()).run())
        .getOrThrow();

    final first = ConversionSession(pollInterval: const Duration(milliseconds: 20));
    var cancelled = false;
    final sub = first.progress.collect().listen((s) {
      if (!cancelled && s.chaptersDone >= 1) {
        cancelled = true;
        first.cancel();
      }
    });
    await first.start(request);
    await first.finished.timeout(const Duration(seconds: 60));
    expect(first.progress.value.phase, ConversionPhase.cancelled);
    await sub.cancel();
    await first.dispose();
    expect(File(entry.project.m4bPath).existsSync(), isFalse);

    final callsBefore = server.requests.length;
    final second = ConversionSession(pollInterval: const Duration(milliseconds: 20));
    await second.start(request);
    await second.finished.timeout(const Duration(seconds: 60));
    expect(second.progress.value.phase, ConversionPhase.finished);
    expect(second.progress.value.log.join('\n'), contains('already done, skipping'));
    expect(server.requests.length, greaterThan(callsBefore));
    await second.dispose();
  });

  test('a dead server is reported as a failure, not a hang', () async {
    final request = (await JobBuilder(
      AppSettings(workspaceDir: tmp.path, kokoroUrl: 'not a url'),
    ).build(entry, voice: const VoiceSettings()).run())
        .getOrThrow();
    final session = ConversionSession(pollInterval: const Duration(milliseconds: 20));
    await session.start(request);
    await session.finished.timeout(const Duration(seconds: 60));
    expect(session.progress.value.phase, ConversionPhase.failed);
    expect(session.progress.value.error, contains('not a valid Kokoro server URL'));
    await session.dispose();
  });
}
