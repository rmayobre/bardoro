// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:zero_nads/zero_nads.dart';

/// One line of `words.csv`: a word, how often it appears, and its respelling (blank = keep Kokoro's own).
final class WordRow {
  const WordRow(this.word, this.count, [this.pronunciation = '']);

  final String word;
  final int count;
  final String pronunciation;

  WordRow withPronunciation(String value) => WordRow(word, count, value);

  @override
  bool operator ==(Object other) =>
      other is WordRow &&
      other.word == word &&
      other.count == count &&
      other.pronunciation == pronunciation;

  @override
  int get hashCode => Object.hash(word, count, pronunciation);
}

/// Reads and writes `output/<slug>/words.csv` in the exact `word,count,pronunciation` format the Python
/// tools use, so either side can pick the file up.
abstract final class WordsFile {
  static Task<Result<List<WordRow>>> load(String path) => Task(
    () => Result.runAsync<List<WordRow>>(() async {
      final f = File(path);
      if (!await f.exists()) throw FileSystemException('No words file', path);
      return parse(await f.readAsString());
    }),
  );

  static List<WordRow> parse(String content) {
    final rows = parseCsv(
      content.startsWith('﻿') ? content.substring(1) : content,
    ).where((r) => r.isNotEmpty).toList();
    if (rows.isEmpty) return const [];
    final header = [for (final h in rows.first) pyStrip(h).toLowerCase()];
    final wordAt = header.indexOf('word');
    final countAt = header.indexOf('count');
    final spokenAt = header.indexOf('pronunciation');
    if (wordAt < 0) throw const FormatException('words.csv has no "word" column');
    String cell(List<String> r, int i) => i >= 0 && i < r.length ? pyStrip(r[i]) : '';
    return [
      for (final r in rows.skip(1))
        if (cell(r, wordAt).isNotEmpty)
          WordRow(
            cell(r, wordAt),
            int.tryParse(cell(r, countAt)) ?? 0,
            cell(r, spokenAt),
          ),
    ];
  }

  static String format(List<WordRow> rows) {
    final sb = StringBuffer(formatCsvRow(['word', 'count', 'pronunciation']));
    for (final r in rows) {
      sb.write(formatCsvRow([r.word, '${r.count}', r.pronunciation]));
    }
    return sb.toString();
  }

  static Task<List<WordRow>> save(String path, List<WordRow> rows) => Task(() async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(format(rows), flush: true);
    await tmp.rename(path);
    return rows;
  });

  /// Rows with a respelling, as the table the pipeline applies (blank rows mean "keep Kokoro's").
  static PronunciationTable toTable(Iterable<WordRow> rows) => {
    for (final r in rows)
      if (r.pronunciation.trim().isNotEmpty) r.word: r.pronunciation.trim(),
  };

  static List<WordRow> fromAnalysis(Iterable<WordCount> words) => [
    for (final w in words) WordRow(w.word, w.count),
  ];
}
