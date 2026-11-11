// SPDX-License-Identifier: GPL-3.0-or-later

import 'lexicon.dart';
import 'phone.dart';
import 'word_pipeline.dart';

/// Regular inflection and derivation on top of lexicon stems: strip a suffix, find the stem in the
/// lexicon, append the suffix phones chosen from the stem's final phone. Suffixes are unstressed, so
/// the stem keeps its lexicon stress. This composes entries that exist; it never guesses a stem.
class MorphResolver implements WordResolver {
  MorphResolver(this.lexicon, {this.minStemLength = 3});

  final Lexicon lexicon;
  final int minStemLength;

  static const _sibilants = {'s', 'z', 'ʃ', 'ʒ', 'ʧ', 'ʤ'};
  static const _voiceless = {'p', 't', 'k', 'f', 'θ', 's', 'ʃ', 'ʧ'};

  /// Same conventions as the lexicon (`ᵻz`, `ᵻd`, `ɪŋ`, `əɹ`, `ᵊl`).
  static List<String> _plural(String last) =>
      _sibilants.contains(last) ? ['ᵻ', 'z'] : (_voiceless.contains(last) ? ['s'] : ['z']);

  static List<String> _past(String last) =>
      last == 't' || last == 'd' ? ['ᵻ', 'd'] : (_voiceless.contains(last) ? ['t'] : ['d']);

  static final _suffixes = <_Suffix>[
    _Suffix('ness', ['n', 'ə', 's'], const [(0, '')]),
    _Suffix('less', ['l', 'ə', 's'], const [(0, '')]),
    _Suffix('ment', ['m', 'ə', 'n', 't'], const [(0, '')]),
    _Suffix('ful', ['f', 'ᵊ', 'l'], const [(0, '')]),
    _Suffix('ly', ['l', 'i'], const [(0, '')]),
    _Suffix('ing', ['ɪ', 'ŋ'], const [(0, ''), (0, 'e'), (1, '')]),
    _Suffix('est', ['ᵻ', 's', 't'], const [(0, ''), (0, 'e'), (1, ''), (0, '~y')]),
    _Suffix('er', ['ə', 'ɹ'], const [(0, ''), (0, 'e'), (1, ''), (0, '~y')]),
    _Suffix('ies', null, const [(0, 'y')], allomorph: _plural),
    _Suffix('ied', null, const [(0, 'y')], allomorph: _past),
    _Suffix('ed', null, const [(0, ''), (0, 'e'), (1, '')], allomorph: _past),
    _Suffix("'s", null, const [(0, '')], allomorph: _plural),
    _Suffix('es', null, const [(0, ''), (0, 'e')], allomorph: _plural),
    _Suffix('s', null, const [(0, '')], allomorph: _plural),
  ];

  @override
  WordPhones? resolve(String word) {
    for (final suf in _suffixes) {
      if (!word.toLowerCase().endsWith(suf.text)) continue;
      final base = word.substring(0, word.length - suf.text.length);
      for (final (undouble, add) in suf.stemEdits) {
        var stem = base;
        if (undouble == 1) {
          if (stem.length < 2 || stem[stem.length - 1] != stem[stem.length - 2]) continue;
          stem = stem.substring(0, stem.length - 1);
        }
        if (add == '~y') {
          // "happier"/"happiest": spelling changed y to i before the suffix
          if (!stem.toLowerCase().endsWith('i')) continue;
          stem = '${stem.substring(0, stem.length - 1)}y';
        } else {
          stem = '$stem$add';
        }
        if (stem.length < minStemLength) continue;
        final phones = lexicon.lookupPhones(stem);
        if (phones == null || !phones.any((p) => p.isVowel)) continue;
        final tail = suf.phones ?? suf.allomorph!(phones.last.symbol);
        return WordPhones([...phones, for (final s in tail) Phone(s)], Source.morphology);
      }
    }
    return null;
  }
}

class _Suffix {
  _Suffix(this.text, this.phones, this.stemEdits, {this.allomorph});

  final String text;

  /// Fixed suffix phones, or null when [allomorph] picks them from the stem's last phone.
  final List<String>? phones;
  final List<String> Function(String lastPhone)? allomorph;

  /// (1 to undouble the final consonant, text appended to the stem or `~y` to turn a final i back
  /// into y), tried in order.
  final List<(int, String)> stemEdits;
}
