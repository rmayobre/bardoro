// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

List<String> split(String raw) =>
    const Syllabifier().split(raw.split(' ')).map((s) => s.symbols.join()).toList();

void main() {
  group('Syllabifier', () {
    test('maximal onset', () {
      expect(split('ɛ l ɛ n d ɪ l'), ['ɛ', 'lɛn', 'dɪl']);
      expect(split('æ s t ɹ ə'), ['æ', 'stɹə']);
      expect(split('ɑ ɹ t ɪ s t'), ['ɑɹ', 'tɪst']);
      expect(split('k ɹ ɪ s t ə f ɜ ɹ'), ['kɹɪ', 'stə', 'fɜɹ']);
    });

    test('single consonants between vowels join the next syllable', () {
      expect(split('t ɑ ɹ ɪ n'), ['tɑ', 'ɹɪn']);
    });

    test('illegal onsets split: ŋ, tl, nd', () {
      expect(split('s ɪ ŋ ɜ ɹ'), ['sɪŋ', 'ɜɹ']);
      expect(split('æ t l ə s'), ['æt', 'ləs']);
    });

    test('hiatus: adjacent vowels are separate nuclei', () {
      expect(split('ɪ d i ə'), ['ɪ', 'di', 'ə']);
    });

    test('affricates are single consonants and clusters of 3 need s + stop + liquid', () {
      expect(split('b æ ʤ ɪ s'), ['bæ', 'ʤɪs']);
      expect(Syllabifier.isLegalOnset(['s', 't', 'ɹ']), isTrue);
      expect(Syllabifier.isLegalOnset(['t', 's', 'ɹ']), isFalse);
      expect(Syllabifier.isLegalOnset(['p', 'w']), isFalse);
    });

    test('no vowels, no syllables', () {
      expect(const Syllabifier().split(['s', 't']), isEmpty);
    });

    test('heavy = long nucleus or closed', () {
      final s = const Syllabifier().split('t A b ə l'.split(' '));
      expect(s.first.isHeavy, isTrue);
      expect(const Syllabifier().split(['k', 'æ']).single.isHeavy, isFalse);
      expect(const Syllabifier().split(['k', 'æ', 't']).single.isHeavy, isTrue);
    });
  });
}
