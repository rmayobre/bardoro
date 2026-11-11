// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

void main() {
  final lexicon = Lexicon.load('assets/en_lexicon.txt');
  final rules = RuleParser().parse(File('assets/en_us.rules').readAsStringSync());
  final engine = RuleEngine(rules, finish: const Finisher().call);
  String rule(String w) => renderPhones(engine.resolve(w)!.phones);

  group('StressAssigner via the rule engine', () {
    test('one and two syllables: stress the first', () {
      expect(rule('zuh'), 'zˈʌ');
      expect(rule('Eldrin'), 'ˈɛldɹɪn');
      expect(rule('Kazan'), 'kˈæzən');
    });

    test('three or more: heavy penult else antepenult (Latin rule)', () {
      expect(rule('Elendil'), 'əlˈɛndɪl'); // heavy penult
      expect(rule('Aragorn'), 'ˈæɹəɡəɹn'); // light penult
    });

    test('suffix table moves stress and secondary stress follows', () {
      expect(rule('relocation'), 'ɹˌɛləkˈAʃən');
      expect(rule('automatic'), 'ˌɔtəmˈætɪk');
      expect(rule('electricity'), 'ˌɛləktɹˈɪsɪti');
    });

    test('exactly one primary stress in every word the rules produce', () {
      for (final w in ['Baralon', 'Quenthyl', 'Mirrorhaven', 'Zuh', 'Sarah', 'Thessaly']) {
        final p = engine.resolve(w)!.phones;
        expect(p.where((x) => x.stress == 1).length, 1, reason: w);
      }
    });

    test('unstressed short vowels reduce, long vowels and ɪ stay', () {
      final syl = const Syllabifier().split(['b', 'æ', 't', 'A', 'k', 'ɪ', 'm']);
      expect(renderPhones(const StressAssigner().assign(syl, 'zzzzz')), 'bətˈAkɪm');
    });

    test('no vowels: nothing to stress', () {
      expect(const Finisher()(['s', 't'], 'st'), [const Phone('s'), const Phone('t')]);
    });

    test('custom suffix table is honoured and the word itself is not a suffix', () {
      const a = StressAssigner(suffixes: {'zz': 1});
      final syl = const Syllabifier().split('b æ t ə l ɪ n'.split(' '));
      expect(a.primaryIndex(syl, 'batelinzz'), 2);
      expect(a.primaryIndex(syl, 'zz'), 0);
    });
  });

  group('MorphResolver', () {
    final morph = MorphResolver(lexicon);
    String m(String w) => renderPhones(morph.resolve(w)!.phones);

    test('plural and possessive allomorphs follow the stem', () {
      expect(m('cats'), 'kˈæts');
      expect(m('dogs'), endsWith('z'));
      expect(m('churches'), endsWith('ᵻz'));
      expect(m("knight's"), endsWith('ts'));
    });

    test('past tense allomorphs', () {
      expect(m('walked'), endsWith('kt'));
      expect(m('baked'), endsWith('kt'));
      expect(m('wanted'), endsWith('ᵻd'));
      expect(m('played'), endsWith('d'));
    });

    test('spelling changes: silent e, doubled consonant, y to i', () {
      expect(m('making'), endsWith('ɪŋ'));
      expect(m('running'), 'ɹˈʌnɪŋ');
      expect(m('carries'), endsWith('z'));
      expect(m('happiest'), 'hˈæpiᵻst');
    });

    test('derivational suffixes keep the stem stress', () {
      expect(m('kindness'), endsWith('nəs'));
      expect(m('hopeful'), endsWith('fᵊl'));
      expect(m('slowly'), endsWith('li'));
    });

    test('source is morphology and stress stays on the stem', () {
      final r = morph.resolve('cats')!;
      expect(r.source, Source.morphology);
      expect(r.phones.where((p) => p.stress == 1).length, 1);
    });

    test('unknown stems and tiny stems are not guessed', () {
      expect(morph.resolve('Zuhs'), isNull);
      expect(morph.resolve('Eldrin'), isNull);
      expect(morph.resolve('is'), isNull, reason: 'stem "i" is too short');
    });

    test('case-aware: a capitalised stem found by exact case', () {
      final lex = Lexicon.parse('Mark\tmˈɑɹk\n');
      expect(renderPhones(MorphResolver(lex).resolve('Marks')!.phones), 'mˈɑɹks');
    });
  });

  test('pipeline order lexicon, morphology, rules; unresolved is reported', () {
    final small = Lexicon.parse('cat\tkˈæt\n');
    final pipe = WordPipeline([LexiconResolver(small), MorphResolver(small), engine]);
    expect(pipe.phonemize('cat').source, Source.lexicon);
    expect(pipe.phonemize('cats').source, Source.morphology);
    expect(pipe.phonemize('Eldrin').source, Source.rules);
    expect(pipe.phonemize('Zü'), isA<WordPhones>().having((w) => w.source, 'source', Source.unresolved));
    expect(pipe.unresolved, {'Zü': 1});
  });
}
