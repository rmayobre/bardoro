// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

void main() {
  final glossary = {
    'Urza': 'Er-zuh',
    'Gerrard': 'GAIR-ard',
    'lullabye': 'lullaby',
    'plane shift': 'plane shift',
    'Zuh': 'Zuh', // identity replacement
  };
  final p = Phonemizer.fromDirectory(
    'assets',
    kokoroConfigPath: 'test/fixtures/kokoro_config.json',
    glossary: glossary,
  );
  final vocab = KokoroVocab.fromConfigJson(File('test/fixtures/kokoro_config.json').readAsStringSync());

  group('Reductions', () {
    test('article a, the before consonant and vowel', () {
      expect(p.phonemize('a cat').phonemes, startsWith('ɐ '));
      expect(p.phonemize('the cat').phonemes, startsWith('ðə '));
      expect(p.phonemize('the apple').phonemes, startsWith('ði '));
      expect(p.phonemize('the').phonemes, 'ði');
      expect(p.phonemize('The, cat').phonemes, startsWith('ði,'));
    });

    test('a before punctuation is the letter name', () {
      expect(p.phonemize('Vitamin A.').phonemes, endsWith('ˈA.'));
    });

    test('flapping only touches t/d between a vowel and an unstressed vowel', () {
      expect(renderPhones(Reductions.flapped(parsePhones('wˈɔtəɹ'))), 'wˈɔɾəɹ');
      expect(renderPhones(Reductions.flapped(parsePhones('ˈɑtˈɑ'))), 'ˈɑtˈɑ');
      expect(renderPhones(Reductions.flapped(parsePhones('tˈɔdəɹ'))), 'tˈɔɾəɹ');
      expect(renderPhones(Reductions.flapped(parsePhones('stˈæ'))), 'stˈæ');
      expect(p.phonemize('Baten').phonemes, contains('ɾ'));
      final off = Phonemizer.fromDirectory(
        'assets',
        kokoroConfigPath: 'test/fixtures/kokoro_config.json',
        reductions: const Reductions(flap: false),
      );
      expect(off.phonemize('Baten').phonemes, isNot(contains('ɾ')));
    });

    test('POS cue picks the lexicon variant for heteronyms', () {
      expect(p.phonemize('to live').phonemes, 'tu lˈɪv');
      expect(p.phonemize('a live').phonemes, 'ɐ lˈIv');
      expect(p.phonemize('to wind').phonemes, endsWith('wˈInd'));
      expect(p.phonemize('the wind').phonemes, endsWith('wˈɪnd'));
      expect(posCue(null), isNull);
    });
  });

  group('Phonemizer', () {
    test('sentence with punctuation passes through and words are spaced', () {
      final r = p.phonemize('The cat sat, and I sang!');
      expect(r.phonemes, 'ðə kˈæt sˈæt, ænd ˈI sˈæŋ!');
      expect(r.isClean, isTrue);
    });

    test('tiers: override, glossary respelling, lexicon, morphology, rules', () {
      final r = p.phonemize('[Kokoro](/kˈoʊkəroʊ/) Urza hobbitless Eldrin');
      expect(r.sourceCounts[Source.override], 1);
      expect(r.sourceCounts[Source.respelling], 1);
      expect(r.sourceCounts[Source.morphology], 1);
      expect(r.sourceCounts[Source.rules], 1);
      expect(r.phonemes, startsWith('kˈOkəɹO ˈɜɹzə hˈɑbətləs'));
    });

    test('override is not touched by the glossary and reports dropped symbols', () {
      final r = p.phonemize('[Urza](/ʢɜɹzə/)');
      expect(r.phonemes, 'ɜɹzə');
      expect(r.droppedChars, {'ʢ': 1});
    });

    test('glossary: respelling, plain replacement, multi-word key, possessive', () {
      expect(p.phonemize('Urza').phonemes, 'ˈɜɹzə');
      expect(p.phonemize('Urza').stressGuessed, {'Er-zuh'});
      expect(p.phonemize('Gerrard').stressGuessed, isEmpty, reason: 'GAIR-ard is marked');
      expect(p.phonemize("Urza's").phonemes, 'ˈɜɹzəz');
      expect(p.phonemize('lullabye').phonemes, p.phonemize('lullaby').phonemes);
      expect(p.phonemize('plane shift').phonemes, p.phonemize('plane shift').phonemes);
      expect(p.phonemize('Urzas').sourceCounts[Source.respelling], isNull, reason: 'whole word only');
      expect(p.phonemize('urza').sourceCounts[Source.respelling], isNull, reason: 'case-sensitive');
    });

    test('glossary replacement text is not itself re-substituted', () {
      final q = Phonemizer.fromDirectory(
        'assets',
        kokoroConfigPath: 'test/fixtures/kokoro_config.json',
        glossary: {'cat': 'dog', 'dog': 'cat'},
      );
      expect(q.phonemize('cat').phonemes, p.phonemize('dog').phonemes);
      expect(q.phonemize('dog').phonemes, p.phonemize('cat').phonemes);
    });

    test('unresolved words are reported and omitted, never guessed', () {
      final r = p.phonemize('Eldrin of Zü and Zü');
      expect(r.unresolved, {'Zü': 2});
      expect(r.phonemes, isNot(contains('z')), reason: 'nothing was invented for Zü');
      expect(r.sourceCounts[Source.unresolved], 2);
      expect(r.isClean, isFalse);
    });

    test('dropped characters and unsupported markup are reported', () {
      final r = p.phonemize('Hi 3 [x](+1) # apples');
      expect(r.droppedChars, {'3': 1, '#': 1});
      expect(r.unsupportedMarkup, ['[x](+1)']);
      expect(r.phonemes, 'hˈI ˈæpᵊlz');
    });

    test('dashes, curly quotes, apostrophes and hyphenated words', () {
      final r = p.phonemize('“Well-known” – it’s Urza’s.');
      expect(r.phonemes, startsWith('“wˈɛl nˈOn” — '));
      expect(r.phonemes, contains('ˈɜɹzəz.'));
      expect(r.droppedChars, isEmpty);
    });

    test('empty and whitespace-only text', () {
      expect(p.phonemize('').phonemes, '');
      expect(p.phonemize('  \n ').phonemes, '');
    });

    test('output only ever contains Kokoro vocab symbols', () {
      final r = p.phonemize('The quick brown fox, Eldrin! Dominaria? “Ok” — (maybe)… Zuhgrath; Kazan: Aragorn.');
      final bad = r.phonemes.runes.map(String.fromCharCode).where((c) => !vocab.contains(c));
      expect(bad, isEmpty);
    });

    test('rule hits are recorded for rule-derived words', () {
      final q = Phonemizer.fromDirectory('assets', kokoroConfigPath: 'test/fixtures/kokoro_config.json');
      q.phonemize('Eldrin');
      expect(q.ruleHits, isNotEmpty);
    });
  });
}
