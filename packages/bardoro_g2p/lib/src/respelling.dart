// SPDX-License-Identifier: GPL-3.0-or-later

import 'phone.dart';
import 'rules/rule_engine.dart';
import 'rules/rule_parser.dart';
import 'stress.dart';
import 'syllables.dart';
import 'word_pipeline.dart';

/// Turns a glossary respelling such as `Er-zuh` into phones.
///
/// Convention (chosen to fit the existing `glossaries/*.csv`, which all use plain lower-case
/// pieces with only an initial capital, and nothing in all caps):
/// - Pieces are separated by `-` and each piece is one syllable, spelled the way the piece is read
///   (`uh`=ə, `ih`=ɪ, `ah`=ɑ, `ee`=i, `oo`=u, `air`=ɛɹ, `g` is always hard, ...).
/// - A piece written in ALL CAPS with two or more letters carries the primary stress
///   (`ER-zuh`, `Dom-ih-NAIR-ee-uh`); further all-caps pieces carry secondary stress. A capital
///   first letter (`Er-zuh`) means nothing, because glossary words are capitalised anyway.
/// - With no all-caps piece the stress is guessed with the same heuristic as for rule words and the
///   result is flagged [WordPhones.stressGuessed].
/// - Unstressed `uh`/`un` style schwas reduce; the other vowels are kept as written.
class Respelling {
  Respelling(RuleSet pieceRules, {this.syllabifier = const Syllabifier()})
    : _engine = RuleEngine(pieceRules);

  final RuleEngine _engine;
  final Syllabifier syllabifier;
  static const _assigner = StressAssigner(reducible: {'ʌ'});

  /// Piece-rule hit counts (line numbers refer to the combined rule text).
  Map<int, int> get ruleHits => _engine.ruleHits;

  /// True when [value] looks like a respelling: at least two non-empty pieces joined by `-` and
  /// nothing but letters and apostrophes in them.
  static bool looks(String value) =>
      RegExp(r"^[A-Za-z']+(-[A-Za-z']+)+$").hasMatch(value);

  static bool isStressPiece(String piece) => RegExp(r"^[A-Z][A-Z']+$").hasMatch(piece);

  /// Null when [value] is not a respelling or a piece contains a letter no rule can read.
  WordPhones? parse(String value) {
    if (!looks(value)) return null;
    final pieces = value.split('-');
    final syllables = <Syllable>[];
    final pieceOfSyllable = <int>[];
    var pendingOnset = <String>[];
    for (var i = 0; i < pieces.length; i++) {
      final raw = _engine.transcribe(pieces[i]);
      if (raw == null) return null;
      final syl = syllabifier.split(raw);
      if (syl.isEmpty) {
        // consonant-only piece: closes the previous syllable, or opens the next one
        if (syllables.isEmpty) {
          pendingOnset = [...pendingOnset, ...raw];
        } else {
          final last = syllables.removeLast();
          syllables.add(Syllable(last.onset, last.nucleus, [...last.coda, ...raw]));
        }
        continue;
      }
      if (pendingOnset.isNotEmpty) {
        syl[0] = Syllable([...pendingOnset, ...syl[0].onset], syl[0].nucleus, syl[0].coda);
        pendingOnset = [];
      }
      for (final s in syl) {
        syllables.add(s);
        pieceOfSyllable.add(i);
      }
    }
    if (syllables.isEmpty) return null;

    final marked = [
      for (var i = 0; i < pieces.length; i++)
        if (isStressPiece(pieces[i])) i,
    ];
    if (marked.isEmpty) {
      return WordPhones(
        _render(syllables, {_guessPrimary(syllables): 1}),
        Source.respelling,
        stressGuessed: true,
      );
    }
    final stress = <int, int>{};
    for (var k = 0; k < syllables.length; k++) {
      final piece = pieceOfSyllable[k];
      if (!marked.contains(piece)) continue;
      // the first syllable of a marked piece takes the stress
      if (k > 0 && pieceOfSyllable[k - 1] == piece) continue;
      stress[k] = piece == marked.first ? 1 : 2;
    }
    return WordPhones(_render(syllables, stress), Source.respelling);
  }

  /// Heavy for a guess: a closed piece or a diphthong. `ee`/`oo` pieces are not counted, so
  /// `Dom-ih-nair-ee-uh` stresses `nair`, not the `ee`.
  static bool _heavy(Syllable s) =>
      s.coda.isNotEmpty || const {'A', 'I', 'O', 'W', 'Y'}.contains(s.nucleus);

  /// First/second piece for short words, else the Latin rule on pieces, never on an `uh` schwa
  /// (a stress there moves one piece to the right). Spelling suffixes are not used: the pieces are
  /// phonetic, so `-ation`-style endings do not appear in them.
  static int _guessPrimary(List<Syllable> syl) {
    final n = syl.length;
    var i = n <= 2 ? 0 : (_heavy(syl[n - 2]) ? n - 2 : n - 3);
    while (i < n - 1 && syl[i].nucleus == 'ʌ') {
      i++;
    }
    return i;
  }

  List<Phone> _render(List<Syllable> syllables, Map<int, int> stress) {
    final out = <Phone>[];
    for (var i = 0; i < syllables.length; i++) {
      final s = syllables[i];
      final st = stress[i] ?? 0;
      out.addAll(s.onset.map(Phone.new));
      var nucleus = s.nucleus;
      if (st == 0 && _assigner.reducible.contains(nucleus)) nucleus = 'ə';
      if (st != 0 && nucleus == 'ə') nucleus = 'ʌ'; // a stressed "uh" is ʌ, not a schwa
      out.add(Phone(nucleus, stress: st));
      out.addAll(s.coda.map(Phone.new));
    }
    return out;
  }
}

/// Glossary tier: whole-word, case-sensitive lookup (matching how the Python pipeline applies
/// glossaries), then [Respelling.parse] on the value. Values that are not hyphenated
/// pseudo-words (plain replacement text such as `lullaby`) return null here and are handled by
/// text substitution in the facade.
class RespellingResolver implements WordResolver {
  RespellingResolver(this.glossary, this.respelling);

  final Map<String, String> glossary;
  final Respelling respelling;

  @override
  WordPhones? resolve(String word) {
    final value = glossary[word];
    if (value == null || value.isEmpty) return null;
    return respelling.parse(value);
  }
}
