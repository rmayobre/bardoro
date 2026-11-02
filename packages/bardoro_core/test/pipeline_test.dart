// SPDX-License-Identifier: GPL-3.0-or-later
// Port of tests/smoke_test.sh plus the resume rules, against a fake Kokoro server (needs ffmpeg + ffprobe).
import 'dart:convert';
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/epub_builder.dart';
import 'support/fake_kokoro.dart';

Future<List<PipelineEvent>> runJob(
  PipelineJob job,
  TtsEngine engine, {
  CancelToken? cancel,
  void Function(PipelineEvent e)? onEvent,
}) async {
  final events = <PipelineEvent>[];
  await for (final e in PipelineRunner(
    job,
    engine: engine,
    cancel: cancel,
  ).run()) {
    events.add(e);
    onEvent?.call(e);
  }
  return events;
}

Future<List<Map<String, dynamic>>> chapterTags(String file) async {
  final r = await Process.run('ffprobe', [
    '-v',
    'error',
    '-show_chapters',
    '-of',
    'json',
    file,
  ]);
  return List<Map<String, dynamic>>.from(
    (jsonDecode(r.stdout as String)['chapters'] as List),
  );
}

void main() {
  late FakeKokoro server;
  late Directory tmp;
  late Workspace ws;
  late BookProject book;
  late KokoroHttpEngine engine;

  setUp(() async {
    server = await FakeKokoro.start();
    tmp = await Directory.systemTemp.createTemp('pipeline');
    ws = Workspace(tmp.path);
    // an apostrophe in the book's file name on purpose, like the Python smoke test
    final epub = File(p.join(tmp.path, "The Brothers' War - Smoke (2000).epub"))
      ..writeAsBytesSync(smokeEpub());
    book = ws.book('smoke', epubPath: epub.path);
    await Directory(book.dir).create(recursive: true);
    engine = KokoroHttpEngine(server.url, delay: (_) async {});
  });
  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  PipelineJob jobFor({
    PronunciationTable pron = const {},
    VoiceSettings voice = const VoiceSettings(),
    String? epubPath,
  }) => PipelineJob(
    epubPath: epubPath ?? book.epubPath,
    workDir: book.chaptersDir,
    outPath: book.m4bPath,
    pronunciations: pron,
    voice: voice,
  );

  test(
    'phase 1 finds the names; phase 2 converts with glossary + book respellings',
    () async {
      final dict = await WordList.fromFile('assets/dictionary/en_words.txt');
      final words = UnknownWordFinder(
        dict,
      ).find(await EpubReader.open(book.epubPath), minCount: 2);
      expect(words.map((w) => w.word), containsAll(['Urza', 'Mishra']));
      // the user fills in Urza in words.csv; the series glossary knows Mishra
      final csv = wordsCsv(words).replaceFirst(
        RegExp(r'^Urza,(\d+),$', multiLine: true),
        r'Urza,$1,Er-zuh',
      );
      File(book.wordsCsv).writeAsStringSync(csv);
      final glossary = File(p.join(tmp.path, 'gloss.csv'))
        ..writeAsStringSync('word,pronunciation\nMishra,Mish-ruh\n');
      const io = PronunciationFileIO();
      final pron = layered([
        await io.load(glossary),
        await io.load(File(book.wordsCsv)),
      ]);

      final events = await runJob(jobFor(pron: pron), engine);

      expect(events.last, isA<Finished>());
      final done = events.last as Finished;
      expect(done.chapterMarkers, 3);
      expect(File(book.m4bPath).lengthSync(), greaterThan(0));
      expect((await chapterTags(book.m4bPath)).map((c) => c['tags']['title']), [
        'Prologue',
        'Chapter 1',
        'Epilogue',
      ]);
      final sent = server.inputs.join('\n');
      expect(sent, contains('Er-zuh'));
      expect(sent, contains('Mish-ruh'));
      expect(
        sent,
        isNot(contains('Urza')),
        reason: 'the unreplaced name must never reach the server',
      );
      expect(events.whereType<ChapterDone>().length, 3);
      expect(events.whereType<ChapterSkipped>(), isEmpty);

      // the work folder looks like the CLI's
      final names = Directory(
        book.chaptersDir,
      ).listSync().map((f) => p.basename(f.path)).toSet();
      expect(
        names,
        containsAll([
          'chapter_01.flac',
          'chapter_02.flac',
          'chapter_03.flac',
          'convert.log',
          'voice_settings.json',
          'all_chapters.txt',
          'chapters_meta.txt',
          'chapter_01_list.txt',
        ]),
      );
      expect(
        names.where((n) => n.contains('_part_') || n.contains('.part')),
        isEmpty,
      );
      final log = File(book.logFile).readAsStringSync();
      expect(log, contains('Pronunciations applied this run:'));
      expect(
        RegExp(
          r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[1/3\] Prologue: ',
          multiLine: true,
        ).hasMatch(log),
        isTrue,
      );
      expect(jsonDecode(File(book.voiceSettingsJson).readAsStringSync()), {
        'voice': 'am_onyx(4)+am_adam(1)',
        'speed': 1.0,
        'pitch': 0.94,
        'tempo': 0.9,
        'bass_db': 4,
        'fx': true,
      });
      expect(
        jsonDecode(File(book.voiceSettingsJson).readAsStringSync()),
        isNot(contains('engine')),
        reason: 'the HTTP engine records exactly the CLI keys',
      );

      // resume: a second run must not call the server again
      final before = server.requests.length;
      final again = await runJob(jobFor(pron: pron), engine);
      expect(server.requests.length, before);
      expect(again.whereType<ChapterSkipped>().length, 3);
      expect(again.last, isA<Finished>());
    },
  );

  test(
    'a rerun with different voice settings warns and keeps the old voice',
    () async {
      await runJob(jobFor(), engine);
      final events = await runJob(
        jobFor(voice: const VoiceSettings(tempo: 0.7)),
        engine,
      );
      final mismatch = events.whereType<SettingsMismatch>().single;
      expect(mismatch.diff['tempo'], (0.9, 0.7));
      expect(
        events.whereType<LogLine>().map((l) => l.message),
        contains(contains('WARNING: voice settings differ')),
      );
      expect(
        jsonDecode(File(book.voiceSettingsJson).readAsStringSync())['tempo'],
        0.9,
      ); // not rewritten
    },
  );

  test('a record written by Python (1 vs 1.0) is not a mismatch', () async {
    Directory(book.chaptersDir).createSync(recursive: true);
    File(book.voiceSettingsJson).writeAsStringSync(
      '{"voice": "am_onyx(4)+am_adam(1)", "speed": 1, "pitch": 0.94, "tempo": 0.9, "bass_db": 4.0, "fx": true}\n',
    );
    final events = await runJob(jobFor(), engine);
    expect(events.whereType<SettingsMismatch>(), isEmpty);
  });

  test(
    'cancel keeps finished chunks; resuming reuses them and only asks for the rest',
    () async {
      final long = List.generate(
        60,
        (i) => 'Sentence number $i goes on for a little while longer here.',
      ).join(' ');
      final epub = File(p.join(tmp.path, 'long.epub'))
        ..writeAsBytesSync(
          buildEpub({
            'a.xhtml': '<h1>Prologue</h1><p>Short opening.</p>',
            'b.xhtml':
                '<h1>Chapter 1</h1>${List.generate(8, (_) => '<p>$long</p>').join()}',
          }),
        );
      final job = jobFor(epubPath: epub.path);
      final cancel = CancelToken();
      final first = await runJob(
        job,
        engine,
        cancel: cancel,
        onEvent: (e) {
          if (e is ChunkDone && e.chapter == 2 && e.chunk == 2) cancel.cancel();
        },
      );
      expect(first.last, isA<Cancelled>());
      final dir = Directory(book.chaptersDir);
      final files = dir.listSync().map((f) => p.basename(f.path)).toList();
      expect(files, contains('chapter_01.flac'));
      expect(files, isNot(contains('chapter_02.flac')));
      expect(
        files,
        containsAll(['chapter_02_part_001.flac', 'chapter_02_part_002.flac']),
      );
      expect(files.where((f) => f.endsWith('.part')), isEmpty);
      expect(File(book.m4bPath).existsSync(), isFalse);

      // junk that must not be mistaken for finished work: an empty chunk, and an unfinished ffmpeg output
      File(
        p.join(book.chaptersDir, 'chapter_02_part_003.flac'),
      ).writeAsBytesSync([]);
      File(
        p.join(book.chaptersDir, 'chapter_02.part.flac'),
      ).writeAsBytesSync([1, 2, 3]);

      final used =
          server.requests.length; // 1 (chapter 1) + 2 (chapter 2 chunks 1-2)
      final second = await runJob(job, engine);
      expect(second.last, isA<Finished>());
      expect(second.whereType<ChapterSkipped>().single.index, 1);
      expect(second.whereType<ChunkReused>().map((e) => e.chunk), [1, 2]);
      final chunksTotal =
          (second.whereType<ChunkReused>().length +
          second.whereType<ChunkDone>().length);
      expect(
        server.requests.length - used,
        chunksTotal - 2,
        reason: 'only unfinished chunks are requested',
      );
      expect(
        second.whereType<ChunkDone>().first.chunk,
        3,
        reason: 'the empty chunk file was re-synthesized',
      );
      expect(
        Directory(book.chaptersDir)
            .listSync()
            .map((f) => p.basename(f.path))
            .where((n) => n.contains('_part_')),
        isEmpty,
      );
      expect(await chapterTags(book.m4bPath), hasLength(2));
    },
  );

  test(
    'a chunk failure ends the run with Failed and the hint; nothing finished is lost',
    () async {
      server.failWith = (n, body) =>
          n == 2 ? 400 : null; // chapter 2 request fails with a voice error
      server.failBody = 'voice not found';
      final events = await runJob(jobFor(), engine);
      final failed = events.last as Failed;
      expect(failed.message, contains('rejected the voice'));
      expect(failed.hint, contains('am_onyx'));
      expect(File(book.chapterFlac(1)).existsSync(), isTrue);
      expect(File(book.chapterFlac(2)).existsSync(), isFalse);
    },
  );

  test(
    'chapter titles with = ; # and apostrophes survive the FFMETADATA round trip',
    () async {
      final epub = File(p.join(tmp.path, 'odd.epub'))
        ..writeAsBytesSync(
          buildEpub({
            'a.xhtml':
                "<h1>Epilogue - King's Tale; #2 = end</h1><p>Some words to speak.</p>",
            'b.xhtml': '<h1>Epilogue</h1><p>More words to speak.</p>',
          }),
        );
      final events = await runJob(jobFor(epubPath: epub.path), engine);
      expect(events.last, isA<Finished>());
      expect((await chapterTags(book.m4bPath)).map((c) => c['tags']['title']), [
        "Epilogue - King's Tale; #2 = end",
        'Epilogue',
      ]);
    },
  );

  test('an epub with nothing readable fails clearly', () async {
    final epub = File(p.join(tmp.path, 'empty.epub'))
      ..writeAsBytesSync(buildEpub({'a.xhtml': '<p>tiny</p>'}));
    final events = await runJob(jobFor(epubPath: epub.path), engine);
    expect((events.last as Failed).message, 'No readable sections found.');
  });

  test('without ffmpeg the run fails with a clear message', () async {
    final runner = PipelineRunner(
      jobFor(),
      engine: engine,
      ffmpeg: const FfmpegService(ffmpeg: 'definitely-not-ffmpeg'),
    );
    final events = await runner.run().toList();
    expect((events.last as Failed).message, contains('was not found'));
  });
}
