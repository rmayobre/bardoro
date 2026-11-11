// SPDX-License-Identifier: GPL-3.0-or-later

import 'phone.dart';
import 'rules/rule_engine.dart';
import 'syllables.dart';

/// Places stress on a syllabified rule-engine word and reduces unstressed vowels.
///
/// Heuristics (the usual textbook English ones, tuned for invented names):
/// 1. A suffix that pulls stress (`-ic`, `-ity`, `-ation`, ...) fixes the position, counted in
///    syllables from the end of the word.
/// 2. Otherwise one or two syllables: stress the first. Three or more: the penultimate if heavy,
///    else the antepenultimate (Latin stress rule; the last syllable is ignored).
/// 3. A secondary stress goes two syllables before the primary when that syllable exists.
/// 4. Remaining unstressed short vowels reduce to schwa.
class StressAssigner {
  const StressAssigner({this.suffixes = defaultSuffixes, this.reducible = defaultReducible});

  /// Spelling suffix -> which syllable from the word end takes primary stress (1 = last).
  final Map<String, int> suffixes;

  static const defaultSuffixes = <String, int>{
    'ication': 2, 'ation': 2, 'ition': 2, 'ution': 2, 'ically': 4, 'ical': 3, 'icity': 3,
    'ity': 3, 'ities': 3, 'ify': 3, 'ic': 2, 'ics': 2, 'ion': 2, 'ian': 2, 'ial': 2,
    'ious': 2, 'eous': 2, 'eer': 1, 'ese': 1, 'esque': 1, //
  };

  /// Reduces to schwa when unstressed. `ɪ`, the diphthongs and `i`/`u` keep their quality.
  static const defaultReducible = {'æ', 'ɑ', 'ɔ', 'ɛ', 'ʌ', 'ʊ', 'ɜ'};

  /// Vowels that become schwa when unstressed. Respellings use a smaller set.
  final Set<String> reducible;

  /// 0-based index of the primary stressed syllable.
  int primaryIndex(List<Syllable> syl, String word) {
    final n = syl.length;
    if (n <= 1) return 0;
    var bestLen = 0;
    int? fromEnd;
    suffixes.forEach((suffix, pos) {
      if (suffix.length > bestLen && word.length > suffix.length && word.endsWith(suffix)) {
        bestLen = suffix.length;
        fromEnd = pos;
      }
    });
    if (fromEnd != null) return (n - fromEnd!).clamp(0, n - 1);
    if (n == 2) return 0;
    return syl[n - 2].isHeavy ? n - 2 : n - 3;
  }

  List<Phone> assign(List<Syllable> syl, String word) {
    if (syl.isEmpty) return const [];
    final p = primaryIndex(syl, word);
    final out = <Phone>[];
    for (var i = 0; i < syl.length; i++) {
      final s = syl[i];
      final stress = i == p ? 1 : (i == p - 2 ? 2 : 0);
      out.addAll(s.onset.map(Phone.new));
      var nucleus = s.nucleus;
      if (stress == 0 && reducible.contains(nucleus)) nucleus = 'ə';
      out.add(Phone(nucleus, stress: stress));
      out.addAll(s.coda.map(Phone.new));
    }
    return out;
  }
}

/// [WordFinisher] for [RuleEngine]: syllabify, stress, reduce. Words with no vowel keep no stress.
class Finisher {
  const Finisher({this.syllabifier = const Syllabifier(), this.stress = const StressAssigner()});

  final Syllabifier syllabifier;
  final StressAssigner stress;

  List<Phone> call(List<String> raw, String word) {
    final syl = syllabifier.split(raw);
    return syl.isEmpty ? [for (final s in raw) Phone(s)] : stress.assign(syl, word);
  }
}
