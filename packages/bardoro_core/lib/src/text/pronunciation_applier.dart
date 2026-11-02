// SPDX-License-Identifier: GPL-3.0-or-later
import 'py_text.dart';

/// Whole-word, case-sensitive, longest-entry-first replacement (port of `apply_pronunciations`).
///
/// Python's `\b` is reproduced per entry: an entry that starts (or ends) with a word character needs a
/// non-word character (or the edge) beside it; one that starts (or ends) with punctuation needs a word
/// character beside it. Compile once per run and reuse across chapters.
class PronunciationApplier {
  PronunciationApplier(Map<String, String> table)
    : _table = Map.of(table)..remove('') {
    if (_table.isEmpty) {
      _re = null;
      return;
    }
    final words = _table.keys.toList()
      ..sort((a, b) => cpLen(b).compareTo(cpLen(a)));
    final alts = words.map((w) {
      final first = w.runes.first;
      final last = w.runes.last;
      final before = isPyWordRune(first)
          ? '(?<![$pyWordClass])'
          : '(?<=[$pyWordClass])';
      final after = isPyWordRune(last)
          ? '(?![$pyWordClass])'
          : '(?=[$pyWordClass])';
      return '$before${RegExp.escape(w)}$after';
    });
    _re = RegExp('(?:${alts.join('|')})', unicode: true);
  }

  final Map<String, String> _table;
  late final RegExp? _re;

  bool get isEmpty => _table.isEmpty;

  /// [hits] is incremented for every replacement made.
  String apply(String text, {Map<String, int>? hits}) {
    final re = _re;
    if (re == null) return text;
    return text.replaceAllMapped(re, (m) {
      final w = m[0]!;
      if (hits != null) hits[w] = (hits[w] ?? 0) + 1;
      return _table[w]!;
    });
  }
}

String applyPronunciations(
  String text,
  Map<String, String> table, {
  Map<String, int>? hits,
}) => PronunciationApplier(table).apply(text, hits: hits);
