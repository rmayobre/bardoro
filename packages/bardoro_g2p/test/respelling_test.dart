// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

void main() {
  final rules = RuleParser().parse(
    '${File('assets/en_respell.rules').readAsStringSync()}\n'
    '${File('assets/en_us.rules').readAsStringSync()}',
  );
  final vocab = KokoroVocab.fromConfigJson(File('test/fixtures/kokoro_config.json').readAsStringSync());
  final mapper = KokoroMapper(vocab);

  String r(String value, [Respelling? re]) {
    final w = (re ?? Respelling(rules)).parse(value);
    expect(w, isNotNull, reason: value);
    return renderPhones(w!.phones);
  }

  group('Respelling', () {
    test('recognises respellings', () {
      expect(Respelling.looks('Er-zuh'), isTrue);
      expect(Respelling.looks("O-Brien's-zuh"), isTrue);
      expect(Respelling.looks('lullaby'), isFalse, reason: 'plain replacement text, not pieces');
      expect(Respelling.looks('plane shift'), isFalse);
      expect(Respelling.looks('a--b'), isFalse);
      expect(Respelling(rules).parse('lullaby'), isNull);
    });

    test('conventional respelling vowels', () {
      expect(r('Er-zuh'), 'ˈɜɹzə');
      expect(r('Hah-jar'), 'hˈɑʤɑɹ');
      expect(r('Bair-in'), 'bˈɛɹɪn');
      expect(r('Joy-rah'), 'ʤˈYɹɑ');
      expect(r('Git-oo'), 'ɡˈɪtu');
      expect(r('Fy-rex-ee-unz'), 'fIɹˈɛksiənz');
      expect(r('pro-teh-zhays'), 'pɹˈOtɛʒAs');
    });

    test('g and c are hard in respellings, ng is ŋ, ow is W', () {
      expect(r('Gess-tos'), startsWith('ɡ'));
      expect(r('Cess-ih'), startsWith('k'));
      expect(r('Ling-er'), contains('ŋ'));
      expect(r('Row-an'), contains('W'));
    });

    test('ALL-CAPS piece marks primary stress, later ones secondary, initial capital means nothing', () {
      expect(r('Dom-ih-NAIR-ee-uh'), 'dɑmɪnˈɛɹiə');
      expect(r('ER-zuh'), 'ˈɜɹzə');
      expect(r('Er-ZUH'), 'ɜɹzˈʌ', reason: 'a stressed uh is ʌ, not a schwa');
      expect(r('DOM-ih-NAIR-ee-uh'), 'dˈɑmɪnˌɛɹiə');
      final marked = Respelling(rules).parse('ER-zuh')!;
      final unmarked = Respelling(rules).parse('Er-zuh')!;
      expect(marked.stressGuessed, isFalse);
      expect(unmarked.stressGuessed, isTrue);
      expect(marked.phones, unmarked.phones);
      expect(Respelling.isStressPiece('A'), isFalse, reason: 'one capital letter is just a name');
    });

    test('guessed stress: short words first, never on an uh, ee/oo do not attract it', () {
      expect(r('Mish-ruh'), 'mˈɪʃɹə');
      expect(r('Fuh-lah-jee'), 'fəlˈɑʤi');
      expect(r('Dom-ih-nair-ee-uh'), 'dɑmɪnˈɛɹiə');
      expect(r('Ar-jiv-ee-un'), 'ɑɹʤˈɪviən');
    });

    test('unstressed uh and un reduce to schwa, other vowels stay as written', () {
      expect(r('Cap-uh-shen'), 'kˈæpəʃɛn');
      expect(r('Ar-jiv-ee-un'), endsWith('iən'));
      expect(r('Ah-mahl'), 'ˈɑmɑl');
    });

    test('a consonant-only piece joins the neighbouring syllable', () {
      expect(r('Her-kil-s'), 'hˈɜɹkɪls');
      expect(r('s-Cap'), 'skˈæp');
    });

    test('letters with no rule leave the respelling unresolved', () {
      expect(Respelling(rules).parse('Zü-ah'), isNull);
    });

    test('every respelling rule is exercised', () {
      final re = Respelling(rules);
      for (final v in [
        'Eye-ron', 'Ahr-in', 'Hah-jar', 'Air-in', 'Ayr-in', 'Uh-nor', 'Ih-nor', 'Eh-nor',
        'Oh-nor', 'Row-an', 'Awr-in', 'pro-teh', 'Gess-tos', 'Cap-uh', 'Ling-er', //
      ]) {
        re.parse(v);
      }
      final dead = [
        for (final rule in rules.rules)
          if (rule.section.startsWith('respelling') && !re.ruleHits.containsKey(rule.line))
            rule.toString(),
      ];
      expect(dead, isEmpty);
    });
  });

  group('RespellingResolver', () {
    final resolver = RespellingResolver({'Urza': 'Er-zuh', 'lullabye': 'lullaby'}, Respelling(rules));

    test('whole-word, case-sensitive glossary lookup', () {
      expect(resolver.resolve('Urza')!.source, Source.respelling);
      expect(resolver.resolve('urza'), isNull);
      expect(resolver.resolve('Urzas'), isNull);
    });

    test('plain replacement values are left for text substitution', () {
      expect(resolver.resolve('lullabye'), isNull);
    });
  });

  test('every hyphenated respelling in the repo glossaries resolves into the vocab', () {
    final dir = Directory('../../glossaries');
    if (!dir.existsSync()) markTestSkipped('glossaries/ not found');
    var checked = 0;
    final re = Respelling(rules);
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv'))) {
      for (final line in f.readAsLinesSync().skip(1)) {
        final i = line.indexOf(',');
        if (i < 0) continue;
        final value = line.substring(i + 1).trim();
        if (!Respelling.looks(value)) continue;
        final w = re.parse(value);
        expect(w, isNotNull, reason: '${f.path}: $line');
        final text = renderPhones(w!.phones);
        expect(mapper.restrict(text).dropped, isEmpty, reason: line);
        expect(w.phones.where((p) => p.stress == 1).length, 1, reason: '$line -> $text');
        checked++;
      }
    }
    expect(checked, greaterThan(50));
  });

  group('inline overrides', () {
    test('splits plain text, overrides and unsupported markup', () {
      final segs = splitOverrides('Hi [Kokoro](/kˈOkəɹO/) and [x](+1) bye');
      expect(segs.length, 5);
      expect((segs[0] as PlainText).text, 'Hi ');
      final o = segs[1] as OverrideWord;
      expect((o.word, o.ipa), ('Kokoro', 'kˈOkəɹO'));
      expect((segs[3] as UnsupportedMarkup).text, '[x](+1)');
      expect((segs[4] as PlainText).text, ' bye');
    });

    test('text without markup is one plain segment; empty word is unsupported', () {
      expect(splitOverrides('just words').single, isA<PlainText>());
      expect(splitOverrides('[](/a/)').single, isA<UnsupportedMarkup>());
      expect(splitOverrides(''), isEmpty);
    });

    test('Kokoro notation and generic IPA give the same phones; dropped symbols are reported', () {
      final a = resolveOverride(const OverrideWord('Kokoro', 'kˈOkəɹO'), mapper);
      final b = resolveOverride(const OverrideWord('Kokoro', 'kˈoʊkəroʊ'), mapper);
      expect(renderPhones(a.phones.phones), 'kˈOkəɹO');
      expect(b.phones.phones, a.phones.phones);
      expect(a.phones.source, Source.override);
      final c = resolveOverride(const OverrideWord('x', 'kʢa'), mapper);
      expect(c.dropped, ['ʢ']);
    });
  });

  test('rule classes may be defined after use (layered rule files)', () {
    final rs = RuleParser().parse('(a) @V => A\nclass V = e\n');
    expect(rs.rules.single.rightSource, '[e]');
  });
}
