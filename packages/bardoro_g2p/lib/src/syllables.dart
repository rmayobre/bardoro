// SPDX-License-Identifier: GPL-3.0-or-later

import 'phone.dart';

class Syllable {
  const Syllable(this.onset, this.nucleus, this.coda);

  final List<String> onset;
  final String nucleus;
  final List<String> coda;

  /// Long nuclei: the diphthongs and the tense monophthongs i and u.
  static const longNuclei = {'A', 'I', 'O', 'W', 'Y', 'i', 'u'};

  /// Heavy = long nucleus or at least one coda consonant (the usual quantity-sensitive stress rule).
  bool get isHeavy => longNuclei.contains(nucleus) || coda.isNotEmpty;

  List<String> get symbols => [...onset, nucleus, ...coda];

  @override
  String toString() => '${onset.join()}.$nucleus.${coda.join()}';
}

/// Splits a raw phone sequence into syllables: every vowel symbol is a nucleus, and the consonants
/// between two nuclei go to the next syllable's onset as far as the cluster is a legal English onset
/// (maximal onset), the rest to the previous coda.
class Syllabifier {
  const Syllabifier();

  static const _stops = {'p', 'b', 't', 'd', 'k', 'ɡ'};
  static const _fricatives = {'f', 'θ', 'ʃ', 'v', 'ð'};

  /// Legal two- and three-consonant onsets. Single consonants are always legal except ŋ.
  static bool isLegalOnset(List<String> c) {
    if (c.isEmpty) return true;
    if (c.length == 1) return c[0] != 'ŋ';
    if (c.length == 2) {
      final (a, b) = (c[0], c[1]);
      if ((_stops.contains(a) || _fricatives.contains(a)) && (b == 'ɹ' || b == 'l')) {
        // tl, dl, θl are not English onsets
        return !(b == 'l' && (a == 't' || a == 'd' || a == 'θ'));
      }
      if (_stops.contains(a) && b == 'w' && a != 'p' && a != 'b') return true; // tw kw dw ɡw
      if (a == 's') return const {'p', 't', 'k', 'm', 'n', 'l', 'w', 'f'}.contains(b);
      if ((a == 'θ' || a == 'ʃ') && (b == 'w' || b == 'ɹ')) return true;
      if (b == 'j') return a != 'j' && a != 'ŋ' && a != 'ʒ'; // cluster + y: "mute", "tune"
      return false;
    }
    if (c.length == 3) {
      return c[0] == 's' &&
          const {'p', 't', 'k'}.contains(c[1]) &&
          const {'ɹ', 'l', 'w', 'j'}.contains(c[2]);
    }
    return false;
  }

  List<Syllable> split(List<String> raw) {
    final nuclei = <int>[
      for (var i = 0; i < raw.length; i++)
        if (vowelSymbols.contains(raw[i])) i,
    ];
    if (nuclei.isEmpty) return const [];
    final syllables = <Syllable>[];
    var onsetStart = 0;
    for (var n = 0; n < nuclei.length; n++) {
      final v = nuclei[n];
      final nextV = n + 1 < nuclei.length ? nuclei[n + 1] : raw.length;
      final between = raw.sublist(v + 1, nextV);
      List<String> coda;
      List<String> nextOnset;
      if (n + 1 == nuclei.length) {
        coda = between;
        nextOnset = const [];
      } else {
        // longest suffix of the cluster that is a legal onset
        var k = 0;
        while (k < between.length && !isLegalOnset(between.sublist(k))) {
          k++;
        }
        coda = between.sublist(0, k);
        nextOnset = between.sublist(k);
      }
      syllables.add(Syllable(raw.sublist(onsetStart, v), raw[v], coda));
      onsetStart = nextV - nextOnset.length;
    }
    return syllables;
  }
}
