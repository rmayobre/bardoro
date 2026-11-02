// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_core/bardoro_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

void main() {
  final units = readUnits();

  test('constants match the Python module', () {
    final c = units['constants'] as Map<String, dynamic>;
    expect(chunkChars, c['CHUNK_CHARS']);
    expect(minCharsOther, c['MIN_CHARS_OTHER']);
  });

  test('cleanStray', () {
    for (final c in units['cleanStray'] as List) {
      expect(
        cleanStray(c['text'] as String),
        c['result'],
        reason: 'input ${c['text']}',
      );
    }
  });

  test(
    'applyPronunciations: whole word, case-sensitive, longest first, hits',
    () {
      final u = units['applyPronunciations'] as Map<String, dynamic>;
      final table = Map<String, String>.from(u['table'] as Map);
      final applier = PronunciationApplier(table);
      for (final c in u['cases'] as List) {
        final hits = <String, int>{};
        expect(
          applier.apply(c['text'] as String, hits: hits),
          c['result'],
          reason: 'input ${c['text']}',
        );
        expect(hits, Map<String, int>.from(c['hits'] as Map));
      }
      expect(applyPronunciations('Urza', {}), u['emptyTable']);
    },
  );

  test('expandRomanNumerals', () {
    for (final c in units['romanNumerals'] as List) {
      final hits = <String, int>{};
      expect(
        expandRomanNumerals(c['text'] as String, hits: hits),
        c['result'],
        reason: 'input ${c['text']}',
      );
      expect(hits, Map<String, int>.from(c['hits'] as Map));
    }
  });

  test('chunkText', () {
    for (final c in units['chunkText'] as List) {
      expect(
        chunkText(c['text'] as String, limit: c['limit'] as int),
        List<String>.from(c['chunks'] as List),
        reason: 'limit ${c['limit']}, ${(c['text'] as String).length} units',
      );
    }
  });

  test(
    'cleanTitleCase differs from Python str.title() only after apostrophes',
    () {
      expect(
        cleanTitleCase('CHAPTER THE HOLLOW KING'),
        'Chapter The Hollow King',
      );
      expect(
        cleanTitleCase("DON'T"),
        "Don't",
      ); // Python: "Don'T" (documented diff)
      expect(
        cleanTitleCase('1ST GATE'),
        '1St Gate',
      ); // same as Python: digits are not letters
    },
  );
}
