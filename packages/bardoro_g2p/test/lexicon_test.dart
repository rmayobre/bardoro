// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

void main() {
  test('parse and lookup with POS variants', () {
    final lex = Lexicon.parse('# c\nread\tɹˈid\tVBD=ɹˈɛd\ncat\tkˈæt\n');
    expect(lex.length, 2);
    expect(lex.lookup('read'), 'ɹˈid');
    expect(lex.lookup('read', pos: 'VBD'), 'ɹˈɛd');
    expect(lex.lookup('read', pos: 'NOUN'), 'ɹˈid', reason: 'falls back to DEFAULT');
    expect(lex.lookup('Cat'), 'kˈæt', reason: 'lower-case fallback');
    expect(lex.lookup('dog'), isNull);
  });

  test('exact case wins and lower case is never promoted to a name', () {
    final lex = Lexicon.parse('Mark\tmˈɑɹk\nsmith\tsmˈɪθ\n');
    expect(lex.lookup('Smith'), 'smˈɪθ');
    expect(Lexicon.parse('Smith\tx\n').lookup('smith'), isNull);
  });

  test('bad lines are rejected', () {
    expect(() => Lexicon.parse('onlyword\n'), throwsFormatException);
  });

  test('phones round-trip with stress marks before the vowel', () {
    final p = parsePhones('fɹˈAd');
    expect(p.map((e) => e.symbol).join(), 'fɹAd');
    expect(p[2], const Phone('A', stress: 1));
    expect(renderPhones(p), 'fɹˈAd');
    expect(parsePhones('ˌɪnfɚmˈeɪʃ').first.stress, 2);
  });

  test('real lexicon covers common words', () {
    final lex = Lexicon.load('assets/en_lexicon.txt');
    expect(lex.length, greaterThan(150000));
    for (final w in ['the', 'name', 'knight', 'through', 'colonel']) {
      expect(lex.contains(w), isTrue, reason: w);
    }
    expect(lex.lookup('wind', pos: 'VERB'), isNot(lex.lookup('wind')));
  });
}
