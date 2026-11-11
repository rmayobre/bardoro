// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

void main() {
  final vocab = KokoroVocab.fromConfigJson(
    File('test/fixtures/kokoro_config.json').readAsStringSync(),
  );
  final mapper = KokoroMapper(vocab);
  final lexicon = Lexicon.load('assets/en_lexicon.txt');

  test('vocab fixture is the 114-symbol Kokoro vocab', () {
    expect(vocab.symbols.length, 114);
  });

  test('single-character diphthongs exist in the vocab', () {
    for (final s in ['A', 'I', 'O', 'W', 'Y']) {
      expect(vocab.contains(s), isTrue, reason: s);
    }
    // And the multi-character forms do not: the model has no 'eɪ' token, only e and ɪ separately.
    expect(mapper.fromIpa('eɪ aɪ oʊ aʊ ɔɪ').text, 'A I O W Y');
  });

  test('every internal phone and stress mark is in the vocab', () {
    final missing = [
      ...phoneInventory,
      primaryStressMark,
      secondaryStressMark,
    ].where((s) => !vocab.contains(s));
    expect(missing, isEmpty);
  });

  test('no lexicon symbol is missing from the vocab', () {
    final used = lexicon.symbolsUsed();
    final bad = used.where((s) => !vocab.contains(s)).toList();
    expect(bad, isEmpty);
    // and every lexicon symbol is inside the internal inventory or is a stress mark
    final allowed = {...phoneInventory, primaryStressMark, secondaryStressMark};
    expect(used.difference(allowed), isEmpty);
  });

  test('no lexicon entry loses a character through the mapper', () {
    var dropped = 0;
    for (final w in ['cause', 'name', 'read', 'wind', 'colonel', 'thought']) {
      final r = mapper.restrict(lexicon.lookup(w)!);
      dropped += r.dropped.length;
    }
    expect(dropped, 0);
  });

  test('symbols outside the vocab are dropped and reported', () {
    final r = mapper.fromIpa('ʢaɪ');
    expect(r.text, 'I');
    expect(r.dropped, ['ʢ']);
  });

  test('generic IPA variants map to Kokoro symbols', () {
    expect(mapper.fromIpa('dʒɔɪ').text, 'ʤY');
    expect(mapper.fromIpa('t͡ʃɑːɹ').text, 'ʧɑɹ');
    expect(mapper.fromIpa('ɡɪft rɪŋ').text, 'ɡɪft ɹɪŋ');
  });
}
