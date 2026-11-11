// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/epub_builder.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('svc'));
  tearDown(() => tmp.delete(recursive: true));

  group('SettingsStore', () {
    test('missing file gives defaults; save then load round-trips', () async {
      final store = SettingsStore(
        p.join(tmp.path, 'cfg', 'settings.json'),
        defaultWorkspace: '/ws',
      );
      final fresh = await store.load().run();
      expect(fresh.workspaceDir, '/ws');
      expect(fresh.kokoroUrlOption.isNone, isTrue);

      final saved = fresh.copyWith(
        kokoroUrl: ' https://k.example ',
        glossaries: ['a.csv'],
      );
      await store.save(saved).run();
      final back = await store.load().run();
      expect(back, saved);
      expect(back.kokoroUrlOption.getOrThrow(), 'https://k.example');
    });

    test('a corrupt file still starts the app with defaults', () async {
      final f = File(p.join(tmp.path, 'settings.json'))..writeAsStringSync('{nope');
      final s = await SettingsStore(f.path, defaultWorkspace: '/ws').load().run();
      expect(s.workspaceDir, '/ws');
    });
  });

  group('LibraryService', () {
    test('status follows the files on disk', () async {
      final ws = Workspace(tmp.path);
      final lib = LibraryService(ws);
      expect(await lib.scan().run(), isEmpty);

      final src = File(p.join(tmp.path, "The Brothers' War.epub"))
        ..writeAsBytesSync(smokeEpub());
      final imported = (await lib.import(src.path).run()).getOrThrow();
      expect(imported.status, BookStatus.needsWords);
      expect(imported.slug, 'The_Brothers_War');
      expect(File(p.join(ws.booksDir, "The Brothers' War.epub")).existsSync(), isTrue);

      final book = imported.project;
      await Directory(book.chaptersDir).create(recursive: true);
      File(book.wordsCsv)
        ..createSync(recursive: true)
        ..writeAsStringSync('word,count,pronunciation\n');
      expect((await lib.scan().run()).single.status, BookStatus.ready);

      File(book.chapterFlac(1)).writeAsStringSync('x');
      final inProgress = (await lib.scan().run()).single;
      expect(inProgress.status, BookStatus.inProgress);
      expect(inProgress.chaptersFinished, 1);

      File(book.m4bPath).writeAsStringSync('x');
      expect((await lib.scan().run()).single.status, BookStatus.done);
    });

    test('importing a non-epub or missing file is a failure, not a throw', () async {
      final lib = LibraryService(Workspace(tmp.path));
      expect((await lib.import('${tmp.path}/x.pdf').run()).isFailure, isTrue);
      expect((await lib.import('${tmp.path}/x.epub').run()).isFailure, isTrue);
    });

    test('seed never overwrites user edits', () async {
      final ws = Workspace(tmp.path);
      File(p.join(ws.glossariesDir, 'a.csv'))
        ..createSync(recursive: true)
        ..writeAsStringSync('mine');
      final written = await LibraryService.seed(ws, {
        'glossaries/a.csv': 'bundled',
        'glossaries/b.csv': 'bundled',
      }).run();
      expect(written, 1);
      expect(File(p.join(ws.glossariesDir, 'a.csv')).readAsStringSync(), 'mine');
      expect(await LibraryService(ws).glossaryNames().run(), ['a.csv', 'b.csv']);
    });
  });

  group('WordsFile', () {
    test('round-trips, quoting commas, and only filled rows become a table', () {
      final rows = [
        const WordRow('Urza', 12, 'Er-zuh'),
        const WordRow('Tawnos', 4),
        const WordRow('Gix', 3, 'Gicks, quickly'),
      ];
      final text = WordsFile.format(rows);
      expect(text.startsWith('word,count,pronunciation\n'), isTrue);
      expect(WordsFile.parse(text), rows);
      expect(WordsFile.toTable(rows), {'Urza': 'Er-zuh', 'Gix': 'Gicks, quickly'});
    });

    test('accepts the two-column glossary shape too', () {
      expect(
        WordsFile.parse('word,pronunciation\nMishra,Mish-ruh\n'),
        [const WordRow('Mishra', 0, 'Mish-ruh')],
      );
    });
  });

  group('JobBuilder', () {
    test('fails with a clear message when no server URL is set', () async {
      final ws = Workspace(tmp.path);
      final book = ws.book('b', epubPath: '${tmp.path}/b.epub');
      final entry = BookEntry(project: book, status: BookStatus.ready, chaptersFinished: 0);
      final r = await JobBuilder(AppSettings(workspaceDir: tmp.path))
          .build(entry, voice: const VoiceSettings())
          .run();
      expect(r.isFailure, isTrue);
      r.onFailure((e) => expect('$e', contains('Kokoro server URL')));
    });

    test('layers glossaries first and the book last so the book wins', () async {
      final ws = Workspace(tmp.path);
      File(p.join(ws.glossariesDir, 's.csv'))
        ..createSync(recursive: true)
        ..writeAsStringSync('word,pronunciation\nUrza,Series-way\nMishra,Mish-ruh\n');
      final book = ws.book('b', epubPath: '${tmp.path}/b.epub');
      File(book.wordsCsv)
        ..createSync(recursive: true)
        ..writeAsStringSync('word,count,pronunciation\nUrza,9,Er-zuh\nGix,2,\n');
      final entry = BookEntry(project: book, status: BookStatus.ready, chaptersFinished: 0);
      final req = (await JobBuilder(
        AppSettings(workspaceDir: tmp.path, kokoroUrl: 'http://k'),
      ).build(entry, voice: const VoiceSettings(), glossaries: ['s.csv']).run())
          .getOrThrow();
      expect(req.job.pronunciations, {'Urza': 'Er-zuh', 'Mishra': 'Mish-ruh'});
      expect(req.kokoroUrl, 'http://k');
      expect(req.job.workDir, book.chaptersDir);
    });
  });

  group('ConversionProgress', () {
    test('folds pipeline events into progress', () {
      var s = const ConversionProgress().started();
      s = s.apply(const SectionsFound([
        Section(index: 1, title: 'Prologue', text: 'a'),
        Section(index: 2, title: 'One', text: 'b'),
      ]));
      expect(s.totalChapters, 2);
      s = s.apply(const ChunkStarted(1, 1, 4));
      expect((s.currentTitle, s.chunk, s.chunks), ('Prologue', 0, 4));
      s = s.apply(const ChunkDone(1, 2, 10, Duration(seconds: 1)));
      expect(s.fraction, closeTo(0.25, 1e-9)); // half of chapter 1 of 2
      s = s.apply(const ChapterDone(1, 'Prologue', Duration(seconds: 5), Duration(seconds: 9), Duration(seconds: 9)));
      expect(s.chaptersDone, 1);
      expect(s.fraction, 0.5);
      s = s.apply(const LogLine('hello'));
      expect(s.log, ['hello']);
      s = s.apply(const Failed('boom', hint: 'try again'));
      expect((s.phase, s.error, s.hint, s.isTerminal), (ConversionPhase.failed, 'boom', 'try again', true));
    });

    test('the log is capped', () {
      var s = const ConversionProgress();
      for (var i = 0; i < ConversionProgress.maxLogLines + 20; i++) {
        s = s.apply(LogLine('$i'));
      }
      expect(s.log.length, ConversionProgress.maxLogLines);
      expect(s.log.last, '${ConversionProgress.maxLogLines + 19}');
    });
  });
}
