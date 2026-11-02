// SPDX-License-Identifier: GPL-3.0-or-later

/// Helpers that reproduce Python 3 string semantics where Dart differs
/// (FLUTTER_CONVERSION.md §9). Python's `str.isspace`, `\s` and `str.strip()`
/// agree on one whitespace set; Dart's `\s` and `trim()` use a different one.
const pyWhitespaceClass = r'\t\n\u000b\u000c\r\u001c-\u001f \u0085   -     　';

/// Python's `\w` (Unicode letters, numbers, underscore) as a character-class body.
const pyWordClass = r'\p{L}\p{N}_';

final RegExp pyWhitespaceRun = RegExp('[$pyWhitespaceClass]+', unicode: true);
final RegExp _pyWordChar = RegExp('[$pyWordClass]', unicode: true);

bool isPyWhitespace(int codeUnit) {
  switch (codeUnit) {
    case 0x09 || 0x0a || 0x0b || 0x0c || 0x0d || 0x20:
    case >= 0x1c && <= 0x1f:
    case 0x85 ||
        0xa0 ||
        0x1680 ||
        0x2028 ||
        0x2029 ||
        0x202f ||
        0x205f ||
        0x3000:
    case >= 0x2000 && <= 0x200a:
      return true;
  }
  return false;
}

/// Python `str.strip()` (no argument).
String pyStrip(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && isPyWhitespace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isPyWhitespace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

/// Python `str.strip(chars)`.
String pyStripChars(String s, String chars) {
  var start = 0;
  var end = s.length;
  while (start < end && chars.contains(s[start])) {
    start++;
  }
  while (end > start && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}

/// True if a single code point is a Python `\w` character.
bool isPyWordRune(int rune) => _pyWordChar.hasMatch(String.fromCharCode(rune));

/// Python `len()`: code points, not UTF-16 units.
int cpLen(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xdc00 && c <= 0xdfff && i > 0) {
      final prev = s.codeUnitAt(i - 1);
      if (prev >= 0xd800 && prev <= 0xdbff) continue;
    }
    n++;
  }
  return n;
}

/// Python `s[:n]` for a code-point count.
String cpPrefix(String s, int n) {
  if (cpLen(s) <= n) return s;
  return String.fromCharCodes(s.runes.take(n));
}

/// Python `str.isupper()` (at least one cased character, none lowercase).
bool pyIsUpper(String s) => s != s.toLowerCase() && s == s.toUpperCase();

/// Python `str.splitlines()` line boundaries.
List<String> pySplitLines(String s) {
  final lines = <String>[];
  var start = 0;
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    final isBreak =
        c == 0x0a ||
        c == 0x0d ||
        c == 0x0b ||
        c == 0x0c ||
        (c >= 0x1c && c <= 0x1e) ||
        c == 0x85 ||
        c == 0x2028 ||
        c == 0x2029;
    if (isBreak) {
      lines.add(s.substring(start, i));
      if (c == 0x0d && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x0a) i++;
      start = i + 1;
    }
    i++;
  }
  if (start < s.length) lines.add(s.substring(start));
  return lines;
}

/// Python `str(value)` for decoded JSON values.
String pyStr(Object? v) => switch (v) {
  null => 'None',
  true => 'True',
  false => 'False',
  _ => '$v',
};

/// Title case without Python's apostrophe quirk (`"DON'T".title()` is `"Don'T"`).
/// A word is a run of letters, joined by apostrophes. Lowercases all but the first letter.
String cleanTitleCase(String s) {
  final out = StringBuffer();
  var inWord = false;
  final runes = s.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final ch = String.fromCharCode(runes[i]);
    final isLetter = ch.toLowerCase() != ch.toUpperCase();
    final isJoiner =
        (ch == "'" || ch == '’') &&
        inWord &&
        i + 1 < runes.length &&
        String.fromCharCode(runes[i + 1]).toLowerCase() !=
            String.fromCharCode(runes[i + 1]).toUpperCase();
    if (isLetter) {
      out.write(inWord ? ch.toLowerCase() : ch.toUpperCase());
      inWord = true;
    } else if (isJoiner) {
      out.write(ch);
    } else {
      out.write(ch);
      inWord = false;
    }
  }
  return out.toString();
}
