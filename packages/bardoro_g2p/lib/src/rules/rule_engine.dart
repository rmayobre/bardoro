// SPDX-License-Identifier: GPL-3.0-or-later

import '../phone.dart';
import '../word_pipeline.dart';
import 'rule_parser.dart';

/// Turns raw phone symbols into stressed [Phone]s. Step 3 supplies the real one (syllabify, stress,
/// reduce); the default adds no stress.
typedef WordFinisher = List<Phone> Function(List<String> raw, String word);

List<Phone> noStress(List<String> raw, String word) => [for (final s in raw) Phone(s)];

class RuleEngine implements WordResolver {
  RuleEngine(this.rules, {this.finish = noStress});

  final RuleSet rules;
  final WordFinisher finish;

  /// Rule file line to number of times it fired. Rules never listed here are dead on the data seen.
  final ruleHits = <int, int>{};

  /// Raw (unstressed) phone symbols for [word], or null when some letter has no applicable rule.
  /// Matching is on the lower-cased word.
  List<String>? transcribe(String word) => transcribeTraced(word)?.phones;

  /// Like [transcribe], also returning the rule-file line of every rule that fired, in order.
  /// Hits are only counted for words that resolve completely.
  ({List<String> phones, List<int> lines})? transcribeTraced(String word) {
    final w = word.toLowerCase();
    final raw = <String>[];
    final hits = <int>[];
    var i = 0;
    while (i < w.length) {
      Rule? hit;
      for (final r in rules.candidates(w[i])) {
        if (r.matches(w, i)) {
          hit = r;
          break;
        }
      }
      if (hit == null) return null;
      hits.add(hit.line);
      raw.addAll(hit.out);
      i += hit.grapheme.length;
    }
    for (final l in hits) {
      ruleHits.update(l, (n) => n + 1, ifAbsent: () => 1);
    }
    return (phones: raw, lines: hits);
  }

  @override
  WordPhones? resolve(String word) {
    if (word.isEmpty) return null;
    final raw = transcribe(word);
    if (raw == null) return null;
    return WordPhones(finish(raw, word.toLowerCase()), Source.rules);
  }
}
