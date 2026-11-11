// SPDX-License-Identifier: GPL-3.0-or-later

import 'phone.dart';

/// Metric helpers for comparing the rule engine with a reference (a dictionary entry or espeak-ng).
/// Pure functions and counters; the I/O lives in `tool/oracle.dart`.

/// Symbols that differ only in notation are treated as equal when comparing: syllabic schwa,
/// reduced ɪ and ɐ.
List<String> compareForm(Iterable<Phone> phones) => [
  for (final p in phones)
    switch (p.symbol) {
      'ᵊ' || 'ɐ' => 'ə',
      'ᵻ' => 'ɪ',
      final s => s,
    },
];

/// Levenshtein distance between two phone sequences.
int editDistance(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final best = prev[j - 1] + cost;
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      cur[j] = best < del ? (best < ins ? best : ins) : (del < ins ? del : ins);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Edit operations turning [ours] into [ref]: `(ours, ref)` pairs where a null side is a missing or
/// extra phone. Equal pairs are omitted, so the list has `editDistance` entries.
List<(String?, String?)> editOps(List<String> ours, List<String> ref) {
  final n = ours.length, m = ref.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final sub = d[i - 1][j - 1] + (ours[i - 1] == ref[j - 1] ? 0 : 1);
      final del = d[i - 1][j] + 1;
      final ins = d[i][j - 1] + 1;
      d[i][j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
  }
  final ops = <(String?, String?)>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + (ours[i - 1] == ref[j - 1] ? 0 : 1)) {
      if (ours[i - 1] != ref[j - 1]) ops.add((ours[i - 1], ref[j - 1]));
      i--;
      j--;
    } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      ops.add((ours[i - 1], null));
      i--;
    } else {
      ops.add((null, ref[j - 1]));
      j--;
    }
  }
  return ops.reversed.toList();
}

/// Index, counting vowels from the start of the word, of the vowel with primary stress, or null.
int? primaryStressIndex(List<Phone> phones) {
  var v = 0;
  for (final p in phones) {
    if (!p.isVowel) continue;
    if (p.stress == 1) return v;
    v++;
  }
  return null;
}

int vowelCount(List<Phone> phones) => phones.where((p) => p.isVowel).length;

/// Counters for one comparison of ours versus a reference.
class PairStats {
  int words = 0;
  int refPhones = 0;
  int edits = 0;
  int exact = 0;

  /// Words where both sides have 2+ vowels and a primary stress.
  int stressComparable = 0;
  int stressCorrect = 0;

  /// `ours→reference` (or `ours→∅` for an extra phone, `∅→reference` for a missing one) to count.
  final confusions = <String, int>{};

  /// (edit distance, word, ours, reference) of the worst words, for review.
  final worst = <(int, String, String, String)>[];

  double get per => refPhones == 0 ? 0 : edits / refPhones;
  double get exactRate => words == 0 ? 0 : exact / words;
  double get stressAccuracy => stressComparable == 0 ? 0 : stressCorrect / stressComparable;

  /// Adds one word; returns its edit distance.
  int add(String word, List<Phone> ours, List<Phone> ref) {
    final a = compareForm(ours);
    final b = compareForm(ref);
    final d = editDistance(a, b);
    words++;
    refPhones += b.length;
    edits += d;
    if (d == 0) exact++;
    if (d > 0) {
      for (final (o, r) in editOps(a, b)) {
        confusions.update('${o ?? '∅'}→${r ?? '∅'}', (n) => n + 1, ifAbsent: () => 1);
      }
    }
    if (vowelCount(ours) >= 2 && vowelCount(ref) >= 2) {
      final si = primaryStressIndex(ours);
      final ri = primaryStressIndex(ref);
      if (si != null && ri != null) {
        stressComparable++;
        if (si == ri) stressCorrect++;
      }
    }
    if (d > 0) {
      worst.add((d, word, renderPhones(ours), renderPhones(ref)));
      worst.sort((x, y) => y.$1.compareTo(x.$1));
      if (worst.length > 25) worst.removeLast();
    }
    return d;
  }
}

/// Per-rule-line counters: how many words used the rule, and in how many of them the output
/// differed from each reference ("blame": a rule is implicated, not proven wrong).
class RuleStat {
  int words = 0;
  int errorWordsVsLexicon = 0;
  int errorWordsVsEspeak = 0;
}
