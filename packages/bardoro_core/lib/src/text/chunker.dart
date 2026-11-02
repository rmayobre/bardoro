// SPDX-License-Identifier: GPL-3.0-or-later
import 'py_text.dart';

/// Max characters per request, split at paragraph then sentence edges.
const int chunkChars = 2500;

final RegExp _sentenceGap = RegExp(
  '(?<=[.!?])[$pyWhitespaceClass]+',
  unicode: true,
);

/// Python `re.split(r"(?<=[.!?])\s+", s)`.
List<String> _splitSentences(String s) {
  final out = <String>[];
  var last = 0;
  for (final m in _sentenceGap.allMatches(s)) {
    out.add(s.substring(last, m.start));
    last = m.end;
  }
  out.add(s.substring(last));
  return out;
}

/// Port of `chunk_text`. Lengths are code points, as in Python.
List<String> chunkText(String text, {int limit = chunkChars}) {
  final chunks = <String>[];
  var cur = '';
  var curLen = 0;
  for (final para in text.split('\n')) {
    final pieces = cpLen(para) <= limit ? [para] : _splitSentences(para);
    for (final piece in pieces) {
      final pieceLen = cpLen(piece);
      if (cur.isNotEmpty && curLen + pieceLen + 1 > limit) {
        chunks.add(cur);
        cur = '';
        curLen = 0;
      }
      if (cur.isNotEmpty) {
        cur = '$cur\n$piece';
        curLen += 1 + pieceLen;
      } else {
        cur = piece;
        curLen = pieceLen;
      }
    }
    if (cur.isNotEmpty && curLen > limit * 0.7) {
      // keep paragraph-ish boundaries
      chunks.add(cur);
      cur = '';
      curLen = 0;
    }
  }
  if (cur.isNotEmpty) chunks.add(cur);
  return chunks;
}
