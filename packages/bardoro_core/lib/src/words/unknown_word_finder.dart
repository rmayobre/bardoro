// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import '../epub/epub_reader.dart';
import '../glossary/csv.dart';
import '../glossary/pronunciation_files.dart' show compareCodePoints;
import '../text/py_text.dart';
import '../text/stray.dart';

class WordCount {
  const WordCount(this.word, this.count);

  final String word;
  final int count;

  @override
  String toString() => '$word,$count';
}

/// The English word list pyspellchecker uses, lowercase (decision D5). Load once per run.
class WordList {
  WordList(this.words)
    : longest = words.fold(0, (m, w) => w.length > m ? w.length : m);

  factory WordList.fromLines(Iterable<String> lines) => WordList({
    for (final l in lines)
      if (l.isNotEmpty) l,
  });

  static Future<WordList> fromFile(String path) async =>
      WordList.fromLines(await File(path).readAsLines());

  final Set<String> words;
  final int longest;

  /// pyspellchecker's `unknown([w])` for an already-lowercase word: words longer than the longest dictionary
  /// word + 3, and strings Python's `float()` accepts (`inf`, `infinity`), are never reported.
  bool isUnknown(String lower) {
    if (cpLen(lower) > longest + 3) return false;
    if (lower == 'inf' || lower == 'infinity') return false;
    return !words.contains(lower);
  }
}

final RegExp _wordRe = RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)*");
final RegExp _dashes = RegExp('[‐-―-]+');

/// Port of `find_unknown_words.py`. The tokenizer is ASCII-only on purpose (parity): an accented name such as
/// `Éowyn` is read as `owyn`. See docs/FLUTTER_CONVERSION.md §6.4.
class UnknownWordFinder {
  const UnknownWordFinder(this.dictionary);

  final WordList dictionary;

  /// All of the book's document text, as `read_text` builds it.
  String readText(EpubBook book) {
    final parts = <String>[];
    for (final item in book.documents) {
      final buf = StringBuffer();
      var first = true;
      for (final n in documentNodes(item)) {
        for (final s in textNodes(n)) {
          if (!first) buf.write(' ');
          buf.write(s);
          first = false;
        }
      }
      parts.add(buf.toString());
    }
    final text = parts
        .join(' ')
        .replaceAll(strayRe, ' ')
        .replaceAll('’', "'")
        .replaceAll('‘', "'");
    return text.replaceAll(_dashes, ' ');
  }

  List<WordCount> find(
    EpubBook book, {
    int minCount = 2,
    Set<String> known = const {},
  }) {
    final counts = <String, int>{};
    final forms = <String, Map<String, int>>{};
    for (final m in _wordRe.allMatches(readText(book))) {
      final w = _stripSuffix(m[0]!);
      if (w.length < 3 || w.contains("'")) continue;
      final low = w.toLowerCase();
      counts[low] = (counts[low] ?? 0) + 1;
      final f = forms.putIfAbsent(low, () => {});
      f[w] = (f[w] ?? 0) + 1;
    }
    final rows = <(int, String)>[];
    counts.forEach((low, n) {
      if (known.contains(low) || !dictionary.isUnknown(low)) return;
      // max(forms, key=forms.get): the first form seen wins ties
      String best = '';
      var bestN = -1;
      forms[low]!.forEach((form, c) {
        if (c > bestN) {
          best = form;
          bestN = c;
        }
      });
      if (n >= minCount) rows.add((n, best));
    });
    // sorted(..., reverse=True) on (count, word) tuples
    rows.sort(
      (a, b) =>
          a.$1 != b.$1 ? b.$1.compareTo(a.$1) : compareCodePoints(b.$2, a.$2),
    );
    return [for (final (n, w) in rows) WordCount(w, n)];
  }
}

/// Reduce possessives to the base word: Urza's -> Urza, Orcs' -> Orcs.
String _stripSuffix(String word) {
  final l = word.toLowerCase();
  if (l.endsWith("'s")) return word.substring(0, word.length - 2);
  if (l.endsWith("s'")) return word.substring(0, word.length - 1);
  return word;
}

/// `word,count,pronunciation` with a blank third column, `\n` line endings.
String wordsCsv(List<WordCount> rows) {
  final sb = StringBuffer(formatCsvRow(['word', 'count', 'pronunciation']));
  for (final r in rows) {
    sb.write(formatCsvRow([r.word, '${r.count}', '']));
  }
  return sb.toString();
}
