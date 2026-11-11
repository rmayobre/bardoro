// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:bardoro_g2p/src/rules/rule_engine.dart';
import 'package:bardoro_g2p/src/rules/rule_parser.dart';
import 'package:test/test.dart';

RuleSet parse(String text) => RuleParser().parse(text);

RuleEngine engineFor(String rules) => RuleEngine(parse(rules));

void main() {
  group('parser', () {
    test('classes expand and contexts compile', () {
      final rs = parse('class V = a e\n^ (b) @V+ => b\n');
      final r = rs.rules.single;
      expect(r.leftSource, '^');
      expect(r.rightSource, '[ae]+');
      expect(r.matches('bae', 0), isTrue);
      expect(r.matches('b', 0), isFalse);
      expect(r.matches('abe', 1), isFalse, reason: 'left ^ needs word start');
    });

    test(r'$ anchors the end and ^ anchors the start', () {
      final e = engineFor('(a) \$ => A\n^ (b) => b\n(b) => p\n(a) => æ\n');
      expect(e.transcribe('ba'), ['b', 'A']);
      expect(e.transcribe('baa'), ['b', 'æ', 'A']);
      expect(e.transcribe('ab'), ['æ', 'p']);
    });

    test('alternation and quantifiers', () {
      final e = engineFor('(a) x|y => A\n(a) => æ\n(x) => k\n(y) => j\n(b) c? => b\n(c) => k\n');
      expect(e.transcribe('ax'), ['A', 'k']);
      expect(e.transcribe('ay'), ['A', 'j']);
      expect(e.transcribe('az'), isNull);
      expect(e.transcribe('bc'), ['b', 'k']);
    });

    test('empty output is silent', () {
      expect(engineFor('(h) =>\n(a) => æ\n').transcribe('hah'), ['æ']);
    });

    test('errors name the line', () {
      void bad(String text, String fragment) => expect(
        () => parse(text),
        throwsA(
          isA<RuleParseException>()
              .having((e) => e.line, 'line', 2)
              .having((e) => e.message, 'message', contains(fragment)),
        ),
      );
      bad('class V = a\n(a) => zz', 'inventory');
      bad('class V = a\n@W (a) => æ', 'unknown class');
      bad('class V = a\n(a) @V ^ => æ', 'left context');
      bad('class V = a\n\$ (a) => æ', 'right context');
      bad('class V = a\n(a) => æ æ ⁇', 'inventory');
      bad('class V = a\n(a b) => æ', 'need exactly one');
      bad('class V = a\nnonsense', '=>');
      bad('class V = a\nclass V = e', 'twice');
    });
  });

  group('RuleSet ordering', () {
    test('longest grapheme first, then file order, input list untouched', () {
      final input = [
        for (final r in parse('(c) => k\n(ch) => ʧ\n(c) i => s\n(ck) => k\n').rules) r,
      ];
      final before = [...input];
      final rs = RuleSet(input);
      expect(input, before, reason: 'constructor must not mutate its input');
      expect(rs.candidates('c').map((r) => r.grapheme), ['ch', 'ck', 'c', 'c']);
      // same length keeps file order: (c) => k (line 1) before (c) i => s (line 3)
      expect(rs.candidates('c').map((r) => r.line), [2, 4, 1, 3]);
      expect(() => rs.candidates('c').add(input.first), throwsUnsupportedError);
      expect(rs.candidates('z'), isEmpty);
    });
  });

  group('engine', () {
    test('unknown letters make the word unresolvable, not guessed', () {
      final e = engineFor('(a) => æ\n');
      expect(e.transcribe('ab'), isNull);
      expect(e.resolve('ab'), isNull);
      expect(e.ruleHits, isEmpty, reason: 'failed words do not count as hits');
    });

    test('lower-cases the word and counts hits per rule line', () {
      final e = engineFor('(a) => æ\n(b) => b\n');
      expect(e.resolve('ABBA')!.phones.map((p) => p.symbol), ['æ', 'b', 'b', 'æ']);
      expect(e.ruleHits, {1: 2, 2: 2});
    });
  });

  group('en_us.rules golden', () {
    final rules = parse(File('assets/en_us.rules').readAsStringSync());
    final engine = RuleEngine(rules);
    final golden = <String, List<(String, String)>>{};
    var section = '';
    for (final line in File('test/golden/rules_golden.txt').readAsLinesSync()) {
      if (line.startsWith('# --- ')) {
        section = line.substring(6).trim();
      } else if (!line.startsWith('#') && line.contains(' => ')) {
        final i = line.indexOf(' => ');
        (golden[section] ??= []).add((line.substring(0, i), line.substring(i + 4)));
      }
    }

    test('every rule section has golden cases', () {
      expect(rules.sections.where((s) => s.isNotEmpty).toSet().difference(golden.keys.toSet()), isEmpty);
    });

    for (final s in golden.entries) {
      test('section ${s.key}', () {
        for (final (word, want) in s.value) {
          expect(engine.transcribe(word)?.join(' '), want, reason: word);
        }
      });
    }

    test('no dead rules: every rule is exercised by the golden words', () {
      final fresh = RuleEngine(rules);
      for (final cases in golden.values) {
        for (final (word, _) in cases) {
          fresh.transcribe(word);
        }
      }
      final dead = [
        for (final r in rules.rules)
          if (!fresh.ruleHits.containsKey(r.line)) r.toString(),
      ];
      expect(dead, isEmpty);
    });
  });
}
