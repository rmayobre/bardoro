// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'phone.dart';

/// Word to phonemes. Backed by `assets/en_lexicon.txt`, built from misaki's US gold and silver
/// dictionaries (Apache-2.0, see `assets/NOTICE`) by `tool/build_lexicon.dart`.
///
/// File format, one entry per line, tab separated:
/// `word<TAB>DEFAULT phones[<TAB>POS=phones ...]`. Lines starting with `#` are comments.
class Lexicon {
  Lexicon._(this._entries);

  /// An empty lexicon (every lookup misses).
  Lexicon.empty() : _entries = {};

  final Map<String, _Entry> _entries;

  int get length => _entries.length;

  /// Parses the compact text format.
  factory Lexicon.parse(String text) {
    final entries = <String, _Entry>{};
    for (final line in text.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final cols = line.split('\t');
      if (cols.length < 2) {
        throw FormatException('Bad lexicon line (need word<TAB>phones)', line);
      }
      final byPos = <String, String>{};
      for (final c in cols.skip(2)) {
        final eq = c.indexOf('=');
        if (eq <= 0) throw FormatException('Bad POS column', line);
        byPos[c.substring(0, eq)] = c.substring(eq + 1);
      }
      entries[cols[0]] = _Entry(cols[1], byPos);
    }
    return Lexicon._(entries);
  }

  /// Reads a lexicon file (for tests, tools and desktop builds; Flutter apps pass the asset text to
  /// [Lexicon.parse] instead).
  static Lexicon load(String path) =>
      Lexicon.parse(File(path).readAsStringSync());

  /// Raw misaki-style phoneme string, or null when the word is unknown.
  ///
  /// Case handling: an exact-case entry wins (the data has separate `Aaron`/`aaron`-style keys for
  /// proper nouns), then the lower-case entry. The reverse, finding `Smith` from `smith`, is
  /// deliberately not done: it would turn a common word into a name guess.
  String? lookup(String word, {String? pos}) {
    final e = _entries[word] ?? _entries[word.toLowerCase()];
    if (e == null) return null;
    return (pos == null ? null : e.byPos[pos]) ?? e.defaultPhones;
  }

  List<Phone>? lookupPhones(String word, {String? pos}) {
    final s = lookup(word, pos: pos);
    return s == null ? null : parsePhones(s);
  }

  bool contains(String word) =>
      _entries.containsKey(word) || _entries.containsKey(word.toLowerCase());

  /// Every distinct phoneme character used by any entry (for vocab coverage tests).
  Set<String> symbolsUsed() {
    final out = <String>{};
    for (final e in _entries.values) {
      out.addAll(e.defaultPhones.split(''));
      for (final v in e.byPos.values) {
        out.addAll(v.split(''));
      }
    }
    return out;
  }
}

class _Entry {
  const _Entry(this.defaultPhones, this.byPos);
  final String defaultPhones;
  final Map<String, String> byPos;
}
