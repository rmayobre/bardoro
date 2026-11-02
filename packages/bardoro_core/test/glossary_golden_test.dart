// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

void main() {
  final units = readUnits();

  test(
    'load pronunciations from every format, with and without blank rows',
    () async {
      for (final c in units['loadPronunciations'] as List) {
        final table = await const PronunciationFileIO().load(
          File(goldenPath('pron/${c['file']}')),
          keepBlank: c['keepBlank'] as bool,
        );
        expect(
          table,
          Map<String, String>.from(c['table'] as Map),
          reason: '${c['file']} keepBlank=${c['keepBlank']}',
        );
        // dict equality ignores order; later duplicates and order matter to layering
        expect(table.keys.toList(), (c['table'] as Map).keys.toList());
      }
    },
  );

  test('csv writer quoting matches csv.writer', () {
    final w = units['csvWrite'] as Map<String, dynamic>;
    final rows = [
      for (final r in w['rows'] as List) List<String>.from(r as List),
    ];
    expect(rows.map(formatCsvRow).join(), w['text']);
    expect(formatCsvRow(['']), w['singleEmptyField']);
  });

  test('csv reader round-trips what csv.writer wrote', () {
    final w = units['csvWrite'] as Map<String, dynamic>;
    final rows = parseCsv(w['text'] as String);
    expect(rows.first, ['word', 'pronunciation']);
    expect(rows[1], ['a,b', 'q"q']);
    expect(rows[2], ['line\nbreak', 'cr\rhere']);
    expect(rows[4], ['', '']);
  });

  test(
    'a row with more fields than the header is an error, not a crash on a list',
    () {
      expect(
        () => parsePronunciations(
          'word,pronunciation\nA,b,c\n',
          extension: '.csv',
        ),
        throwsFormatException,
      );
    },
  );

  test('layered: later wins, a blank never cancels an earlier respelling', () {
    expect(
      layered([
        {'A': 'x', 'B': 'y'},
        {'A': 'z'},
      ]),
      {'A': 'z', 'B': 'y'},
    );
    final book = parsePronunciations(
      'word,pronunciation\nA,\n',
      extension: '.csv',
    ); // blanks dropped
    expect(
      layered([
        {'A': 'x'},
        book,
      ]),
      {'A': 'x'},
    );
  });

  group('mergeGlossary equals update_glossary.py', () {
    final merges = units['merge'] as Map<String, dynamic>;
    for (final e in merges.entries) {
      test(e.key, () {
        final m = e.value as Map<String, dynamic>;
        final source = parsePronunciations(
          m['source'] as String,
          extension: '.csv',
        );
        final gl = m['glossary'] == null
            ? <String, String>{}
            : parsePronunciations(
                m['glossary'] as String,
                extension: '.csv',
                keepBlank: true,
              );
        final r = mergeGlossary(source, gl, overwrite: m['overwrite'] as bool);
        expect(glossaryCsv(r.result), m['result']);
        final stdout = m['stdout'] as String;
        expect(
          stdout,
          startsWith(
            '${r.added.length} added, ${r.replaced.length} replaced, '
            '${r.conflicts.length} conflicts kept as-is, ${r.result.length} total in glossary',
          ),
        );
        for (final line in r.replaced) {
          expect(stdout, contains('  replaced  $line'));
        }
        for (final line in r.conflicts) {
          expect(
            stdout,
            contains('  conflict  $line (use --overwrite to replace)'),
          );
        }
      });
    }
  });
}
