// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:bardoro_g2p/bardoro_g2p.dart';
import 'package:test/test.dart';

import '../tool/oracle.dart' as oracle;

List<Phone> ph(String s) => parsePhones(s);

void main() {
  group('metrics', () {
    test('edit distance', () {
      expect(editDistance(['a'], ['a']), 0);
      expect(editDistance([], ['a', 'b']), 2);
      expect(editDistance(['k', 'æ', 't'], ['k', 'ɑ', 't']), 1);
      expect(editDistance(['k', 'æ', 't'], ['k', 't']), 1);
      expect(editDistance(['a', 'b', 'c'], ['c', 'b', 'a']), 2);
    });

    test('editOps lists exactly the differences', () {
      expect(editOps(['k', 'æ', 't'], ['k', 'ɑ', 't']), [('æ', 'ɑ')]);
      expect(editOps(['k', 't'], ['k', 'æ', 't']), [(null, 'æ')]);
      expect(editOps(['k', 'æ', 'x', 't'], ['k', 'æ', 't']), [('x', null)]);
      for (final (a, b) in [(['a', 'b', 'c'], ['c', 'b', 'a']), (['s', 'p'], ['p', 's', 'k'])]) {
        expect(editOps(a, b).length, editDistance(a, b));
      }
    });

    test('compare form folds notation variants, not real differences', () {
      expect(compareForm(ph('ᵊɐᵻæ')), ['ə', 'ə', 'ɪ', 'æ']);
    });

    test('stress index counts vowels, ignores consonants', () {
      expect(primaryStressIndex(ph('ɹˌɛləkˈAʃən')), 2);
      expect(primaryStressIndex(ph('kæt')), isNull);
      expect(vowelCount(ph('ɹˌɛləkˈAʃən')), 4);
    });

    test('PairStats aggregates PER, exact rate and stress accuracy (2+ vowels only)', () {
      final s = PairStats();
      expect(s.add('cat', ph('kˈæt'), ph('kˈæt')), 0);
      expect(s.add('dog', ph('dˈɑɡ'), ph('dˈɔɡ')), 1);
      expect(s.add('ab', ph('ˈæbə'), ph('əbˈæ')), 2); // 2 vowels, stress differs
      expect(s.words, 3);
      expect(s.exact, 1);
      expect(s.stressComparable, 1, reason: 'monosyllables do not count');
      expect(s.stressCorrect, 0);
      expect(s.per, closeTo(3 / 9, 1e-9));
      expect(s.confusions['ɑ→ɔ'], 1);
    });
  });

  group('espeak-ng oracle', () {
    final has = oracle.espeakAvailable();

    test('runs end to end and stays within a loose regression bound', () async {
      final report = await oracle.runOracle(sample: 400);
      expect(report, contains('| rules vs lexicon |'));
      expect(report, contains('| rules vs espeak-ng |'));
      final per = double.parse(
        RegExp(r'\| rules vs espeak-ng \| \d+ \| ([\d.]+)%').firstMatch(report)![1]!,
      );
      // Measured around 24% on a 6000-word CMUdict slice; this only catches a broken engine.
      expect(per, lessThan(45));
    }, skip: has ? false : 'espeak-ng is not installed', timeout: const Timeout(Duration(minutes: 2)));

    test('report always renders the lexicon half and the dead-rule section', () async {
      final report = await oracle.runOracle(sample: 200);
      expect(report, contains('| rules vs lexicon |'));
      expect(report, contains('## Dead rules'));
    });
  });

  test('rule trace matches transcribe and counts hits once per resolved word', () {
    final rules = RuleParser().parse(File('assets/en_us.rules').readAsStringSync());
    final e = RuleEngine(rules);
    final t = e.transcribeTraced('knight')!;
    expect(t.phones, e.transcribe('knight'));
    expect(t.lines.length, lessThan('knight'.length));
    expect(e.transcribeTraced('Zü'), isNull);
  });
}
