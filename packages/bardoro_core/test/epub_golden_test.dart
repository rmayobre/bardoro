// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

const books = ['basic', 'images', 'ncx_only', 'accents'];
const pronSets = {
  'none': <String>[],
  'series': ['series.csv'],
  'series_book': ['series.csv', 'book.csv'],
};

Future<PronunciationTable> loadStack(List<String> files) async {
  final tables = [
    for (final f in files)
      await const PronunciationFileIO().load(File(goldenPath('pron/$f'))),
  ];
  return layered(tables);
}

void main() {
  for (final name in books) {
    group(name, () {
      late EpubBook book;
      late List<Section> sections;
      setUpAll(() async {
        book = await EpubReader.open(goldenPath('$name.epub'));
        sections = const SectionExtractor().extract(book);
      });

      test('sections: titles, char counts and text equal extract_sections', () {
        final golden = readGoldenJson('sections_$name.json') as List;
        expect(sections.length, golden.length);
        for (final (i, g) in golden.indexed) {
          expect(sections[i].index, g['index']);
          expect(
            sections[i].title,
            g['title'],
            reason: 'title of section ${i + 1}',
          );
          expect(
            cpLen(sections[i].text),
            g['chars'],
            reason: 'chars of section ${i + 1}',
          );
          expect(
            sections[i].text,
            g['text'],
            reason: 'text of section ${i + 1}',
          );
        }
      });

      for (final entry in pronSets.entries) {
        test(
          'chunks with pronunciations "${entry.key}" equal dump_golden.py',
          () async {
            final applier = PronunciationApplier(await loadStack(entry.value));
            final golden =
                readGoldenJson('chunks_${name}__${entry.key}.json') as List;
            expect(sections.length, golden.length);
            for (final (i, g) in golden.indexed) {
              final spoken = expandRomanNumerals(
                applier.apply(sections[i].text),
              );
              expect(
                chunkText(spoken),
                List<String>.from(g['chunks'] as List),
                reason: 'chunks of section ${i + 1} (${g['title']})',
              );
            }
          },
        );
      }

      for (final minCount in [1, 2]) {
        test(
          'unknown words (min count $minCount) equal find_unknown_words.py',
          () async {
            final dict = await WordList.fromFile(
              'assets/dictionary/en_words.txt',
            );
            final rows = UnknownWordFinder(dict).find(book, minCount: minCount);
            expect(
              wordsCsv(rows),
              File(
                goldenPath('words_${name}_min$minCount.csv'),
              ).readAsStringSync(),
            );
          },
        );
      }
    });
  }
}
