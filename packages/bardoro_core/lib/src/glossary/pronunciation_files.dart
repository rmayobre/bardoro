// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import '../text/py_text.dart';
import 'csv.dart';

/// word -> respelling. An empty respelling means "leave Kokoro's own pronunciation alone".
typedef PronunciationTable = Map<String, String>;

/// Port of `load_pronunciations` (.csv, .json, .txt). The `.py` format is dropped (decision D8): it needs
/// Python's `ast.literal_eval`.
///
/// Blank pronunciations are skipped unless [keepBlank] is true (glossaries keep them to record "reviewed").
PronunciationTable parsePronunciations(
  String content, {
  required String extension,
  bool keepBlank = false,
}) {
  final table = <String, String>{};
  switch (extension.toLowerCase()) {
    case '.csv':
      final rows =
          parseCsv(content.startsWith('﻿') ? content.substring(1) : content)
              .where((r) => r.isNotEmpty) // DictReader skips empty lines
              .toList();
      if (rows.isEmpty) break;
      final header = [for (final h in rows.first) pyStrip(h).toLowerCase()];
      for (final (n, row) in rows.skip(1).indexed) {
        if (row.length > header.length) {
          throw FormatException(
            'CSV row ${n + 2} has ${row.length} fields but the header has ${header.length}; '
            'quote any respelling that contains a comma',
          );
        }
        final byName = <String, String>{};
        for (final (i, h) in header.indexed) {
          byName[h] = i < row.length ? pyStrip(row[i]) : '';
        }
        table[byName['word'] ?? ''] = byName['pronunciation'] ?? '';
      }
    case '.json':
      final data = jsonDecode(
        content.startsWith('﻿') ? content.substring(1) : content,
      );
      if (data is Map) {
        data.forEach((k, v) => table['$k'] = pyStr(v));
      } else if (data is List) {
        for (final d in data) {
          if (d is! Map) {
            throw const FormatException('JSON list entries must be objects');
          }
          table[pyStr(d.containsKey('word') ? d['word'] : '')] = pyStr(
            d.containsKey('pronunciation') ? d['pronunciation'] : '',
          );
        }
      } else {
        throw const FormatException(
          'JSON pronunciations must be an object or a list',
        );
      }
    case '.py':
      throw UnsupportedError(
        '.py pronunciation files are not supported; use .csv, .json or .txt',
      );
    default:
      for (var line in pySplitLines(content)) {
        line = pyStrip(line.split(RegExp('(?:^|[$pyWhitespaceClass])#'))[0]);
        if (line.isEmpty) continue;
        final sep = line.contains('\t') ? '\t' : '=';
        final at = line.indexOf(sep);
        if (at < 0) continue;
        table[pyStrip(line.substring(0, at))] = pyStrip(line.substring(at + 1));
      }
  }
  final out = <String, String>{};
  table.forEach((w, s) {
    final word = pyStrip(w);
    final spoken = pyStrip(s);
    if (word.isNotEmpty && (keepBlank || spoken.isNotEmpty)) out[word] = spoken;
  });
  return out;
}

class PronunciationFileIO {
  const PronunciationFileIO();

  Future<PronunciationTable> load(File f, {bool keepBlank = false}) async {
    if (!await f.exists()) {
      throw FileSystemException('Pronunciation file not found', f.path);
    }
    final ext = f.path.contains('.')
        ? f.path.substring(f.path.lastIndexOf('.'))
        : '';
    return parsePronunciations(
      await f.readAsString(),
      extension: ext,
      keepBlank: keepBlank,
    );
  }

  /// `word,pronunciation`, sorted case-insensitively (stable), `\n` line endings.
  Future<void> writeGlossary(File f, PronunciationTable t) async {
    await f.parent.create(recursive: true);
    await f.writeAsString(glossaryCsv(t));
  }
}

String glossaryCsv(PronunciationTable t) {
  final entries = t.entries.toList();
  final keyed = [
    for (final (i, e) in entries.indexed) (i, e.key.toLowerCase(), e),
  ];
  keyed.sort((a, b) {
    final c = _compareCodePoints(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1); // Python's sort is stable
  });
  final sb = StringBuffer(formatCsvRow(['word', 'pronunciation']));
  for (final k in keyed) {
    sb.write(formatCsvRow([k.$3.key, k.$3.value]));
  }
  return sb.toString();
}

/// Python compares strings by code point; Dart's `compareTo` compares UTF-16 units.
int _compareCodePoints(String a, String b) {
  final ra = a.runes.iterator;
  final rb = b.runes.iterator;
  while (true) {
    final ha = ra.moveNext();
    final hb = rb.moveNext();
    if (!ha || !hb) return ha == hb ? 0 : (ha ? 1 : -1);
    if (ra.current != rb.current) return ra.current.compareTo(rb.current);
  }
}

/// Later tables win. Callers pass tables loaded WITHOUT blank rows, so a blank never cancels a respelling.
PronunciationTable layered(List<PronunciationTable> inOrder) => {
  for (final t in inOrder) ...t,
};

/// Compare strings by code point (exposed for the word finder's sort).
int compareCodePoints(String a, String b) => _compareCodePoints(a, b);
