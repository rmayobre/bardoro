// SPDX-License-Identifier: GPL-3.0-or-later
import 'py_text.dart';

/// Watermark/ad text added by ebook sites, case-insensitive. One-line to extend, like STRAY_RE in Python.
/// `\b` is written as lookarounds so it is Unicode-aware like Python's.
final RegExp strayRe = RegExp(
  r'(?<![' +
      pyWordClass +
      r'])(?:oceanofpdf(?:\.com)?)(?![' +
      pyWordClass +
      r'])',
  caseSensitive: false,
  unicode: true,
);

final RegExp _hasWordChar = RegExp('[$pyWordClass]', unicode: true);

/// Remove watermark text, collapse whitespace; '' if nothing readable is left.
String cleanStray(String text) {
  final t = pyStrip(
    text.replaceAll(strayRe, ' ').replaceAll(pyWhitespaceRun, ' '),
  );
  return _hasWordChar.hasMatch(t) ? t : '';
}
