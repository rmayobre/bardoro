// SPDX-License-Identifier: GPL-3.0-or-later

import 'lexicon.dart';
import 'phone.dart';

enum Source { override, lexicon, morphology, rules, respelling, unresolved }

class WordPhones {
  const WordPhones(this.phones, this.source);
  final List<Phone> phones;
  final Source source;

  @override
  String toString() => '${renderPhones(phones)} ($source)';
}

/// One tier. Return null to pass the word to the next tier.
///
/// Tiers receive the word exactly as written (original case) and decide for themselves whether case
/// matters: the lexicon tier tries the exact case and then lower case; rules lower-case the word.
abstract interface class WordResolver {
  WordPhones? resolve(String word);
}

/// Direct lexicon hit, no stemming.
class LexiconResolver implements WordResolver {
  LexiconResolver(this.lexicon);
  final Lexicon lexicon;

  @override
  WordPhones? resolve(String word) {
    final p = lexicon.lookupPhones(word);
    return p == null ? null : WordPhones(p, Source.lexicon);
  }
}

class WordPipeline {
  WordPipeline(this.tiers);

  /// Tried in order; the first non-null answer wins.
  final List<WordResolver> tiers;
  final _cache = <String, WordPhones>{};

  /// Words no tier could resolve, with how often they were asked for.
  final unresolved = <String, int>{};

  /// The cache is keyed on the word as written, because case can matter (proper nouns).
  WordPhones phonemize(String word) => _cache[word] ??= _run(word);

  WordPhones _run(String word) {
    for (final t in tiers) {
      final r = t.resolve(word);
      if (r != null) return r;
    }
    unresolved.update(word, (n) => n + 1, ifAbsent: () => 1);
    return const WordPhones([], Source.unresolved);
  }
}
