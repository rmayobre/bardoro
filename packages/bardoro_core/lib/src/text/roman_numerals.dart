// SPDX-License-Identifier: GPL-3.0-or-later
import 'py_text.dart';

const _ordinals = [
  'first',
  'second',
  'third',
  'fourth',
  'fifth',
  'sixth',
  'seventh',
  'eighth',
  'ninth',
  'tenth', //
  'eleventh',
  'twelfth',
  'thirteenth',
  'fourteenth',
  'fifteenth',
  'sixteenth',
  'seventeenth',
  'eighteenth', 'nineteenth', 'twentieth',
];
const _cardinals = [
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve', //
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
  'twenty',
];

/// II-XX only: a lone I, V or X is too often a pronoun, a letter or a variable.
final Map<String, int> _roman = {
  for (final (i, r)
      in 'I II III IV V VI VII VIII IX X XI XII XIII XIV XV XVI XVII XVIII XIX XX'
          .split(' ')
          .indexed)
    if (r.length > 1) r: i + 1,
};

/// "Part II", "Book III", "World War II" are counts, read as numbers rather than "the Second".
/// ('world war' can never match the single word captured; it is kept to mirror the Python tuple.)
const romanCountWords = {
  'part',
  'book',
  'chapter',
  'act',
  'volume',
  'vol',
  'section',
  'appendix',
  'phase',
  'stage', //
  'level',
  'episode',
  'season',
  'article',
  'war',
  'world war',
  'class',
  'type',
  'tier',
};

final String _romanAlt =
    (_roman.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join(
      '|',
    );

// Python's \b / \w are Unicode-aware; Dart's are ASCII-only, so use lookarounds.
final RegExp _romanAfterWord = RegExp(
  "(?<![$pyWordClass])([A-Za-z][$pyWordClass'’-]*)([ \\t]+)($_romanAlt)(?![$pyWordClass])",
  unicode: true,
);

/// Spell out Roman numerals II-XX. After a capitalised name: "the Second"; after Part/Book/...: "two".
/// [hits] is incremented per replacement, keyed by the matched text.
String expandRomanNumerals(String text, {Map<String, int>? hits}) {
  return text.replaceAllMapped(_romanAfterWord, (m) {
    final word = m[1]!;
    final space = m[2]!;
    final n = _roman[m[3]!]!;
    final String spoken;
    if (romanCountWords.contains(word.toLowerCase())) {
      spoken = '$word$space${_cardinals[n - 1]}';
    } else if (word.codeUnitAt(0) >= 0x41 && word.codeUnitAt(0) <= 0x5a) {
      final o = _ordinals[n - 1];
      spoken = '$word${space}the ${o[0].toUpperCase()}${o.substring(1)}';
    } else {
      return m[0]!;
    }
    if (hits != null) hits[m[0]!] = (hits[m[0]!] ?? 0) + 1;
    return spoken;
  });
}
