// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

/// The symbols Kokoro's model accepts: the `vocab` object of `hexgrad/Kokoro-82M` `config.json`.
class KokoroVocab {
  KokoroVocab(this.symbols);

  /// Parses a full `config.json` (or any JSON with a top-level `vocab` object).
  factory KokoroVocab.fromConfigJson(String json) {
    final vocab = (jsonDecode(json) as Map<String, dynamic>)['vocab'];
    if (vocab is! Map) throw const FormatException('config.json has no vocab');
    return KokoroVocab(vocab.keys.cast<String>().toSet());
  }

  final Set<String> symbols;

  bool contains(String symbol) => symbols.contains(symbol);
}

class MapResult {
  const MapResult(this.text, this.dropped);

  /// Phonemes, restricted to the vocab.
  final String text;

  /// Characters that were not in the vocab and were removed (in order, with repeats).
  final List<String> dropped;
}

/// Generic IPA digraphs and variants to the single symbols Kokoro uses. Longest match first.
/// Internal phones are already Kokoro symbols, so this only matters for external IPA (overrides,
/// the espeak oracle). Entries are IPA identities, not pronunciation data.
const _ipaToKokoro = <String, String>{
  'eɪ': 'A',
  'aɪ': 'I',
  'oʊ': 'O',
  'əʊ': 'Q',
  'aʊ': 'W',
  'ɔɪ': 'Y',
  'dʒ': 'ʤ',
  'tʃ': 'ʧ',
  'ɚ': 'əɹ',
  'ɝ': 'ɜɹ',
  'ɜː': 'ɜ',
  'ɑː': 'ɑ',
  'ɔː': 'ɔ',
  'uː': 'u',
  'iː': 'i',
  'g': 'ɡ',
  'r': 'ɹ',
  'ɐ': 'ə',
  'ʍ': 'w',
  'ɫ': 'l',
  '͡': '', // tie bar in t͡ʃ, d͡ʒ: removed before digraph lookup
  '͜': '',
};

class KokoroMapper {
  KokoroMapper(this.vocab);

  final KokoroVocab vocab;

  /// Maps generic IPA to Kokoro symbols, then drops (and reports) anything not in the vocab.
  MapResult fromIpa(String ipa) {
    final cleaned = ipa.replaceAll('͡', '').replaceAll('͜', '');
    final sb = StringBuffer();
    final keys = _ipaToKokoro.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var i = 0;
    outer:
    while (i < cleaned.length) {
      for (final k in keys) {
        if (k.isNotEmpty && cleaned.startsWith(k, i)) {
          sb.write(_ipaToKokoro[k]);
          i += k.length;
          continue outer;
        }
      }
      sb.write(cleaned[i]);
      i++;
    }
    return restrict(sb.toString());
  }

  /// Keeps only vocab symbols from text that is already in Kokoro notation.
  MapResult restrict(String text) {
    final kept = StringBuffer();
    final dropped = <String>[];
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      if (vocab.contains(ch)) {
        kept.write(ch);
      } else {
        dropped.add(ch);
      }
    }
    return MapResult(kept.toString(), dropped);
  }
}
