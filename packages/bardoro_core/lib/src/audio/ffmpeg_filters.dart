// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

/// asetrate shifts pitch (and speed by the same factor); atempo then sets the final speed.
String buildFilter(int sampleRate, num pitch, num tempo, num bassDb) =>
    'asetrate=${(sampleRate * pitch).toInt()},aresample=$sampleRate,'
    'atempo=${(tempo / pitch).toStringAsFixed(5)},bass=g=$bassDb:f=150';

/// ffmpeg concat list entries are single-quoted; a literal ' must be written as '\''.
String concatLine(String path) =>
    "file '${File(path).absolute.path.replaceAll("'", r"'\''")}'\n";

/// Backslash-escape `= ; # \` and newlines for FFMETADATA values.
String ffEscape(String s) =>
    s.replaceAllMapped(RegExp(r'[=;#\\\n]'), (m) => '\\${m[0]}');

/// Python `fmt_secs`: "1h02m" or "3m05s".
String fmtSecs(num seconds) {
  final sec = seconds.toInt();
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '${h}h${two(m)}m' : '${m}m${two(s)}s';
}
