// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'kokoro_mapper.dart';
import 'lexicon.dart';
import 'morphology.dart';
import 'overrides.dart';
import 'phone.dart';
import 'reductions.dart';
import 'respelling.dart';
import 'rules/rule_engine.dart';
import 'rules/rule_parser.dart';
import 'stress.dart';
import 'word_pipeline.dart';

/// What came out of [Phonemizer.phonemize], including everything that was not handled.
class PhonemizeResult {
  PhonemizeResult({
    required this.phonemes,
    required this.unresolved,
    required this.droppedChars,
    required this.unsupportedMarkup,
    required this.stressGuessed,
    required this.sourceCounts,
  });

  /// Kokoro phoneme string: words separated by spaces, vocab punctuation kept in place.
  final String phonemes;

  /// Words no tier could pronounce (with counts). They are left out of [phonemes], not guessed.
  final Map<String, int> unresolved;

  /// Characters that are not in Kokoro's vocab and not letters (digits, brackets, quotes, ...),
  /// removed from the output, with counts. Number and abbreviation expansion belongs in front of
  /// this package.
  final Map<String, int> droppedChars;

  /// `[..](..)` markup that is not a `/ipa/` override; it is not spoken.
  final List<String> unsupportedMarkup;

  /// Respellings whose stress was guessed (no ALL-CAPS piece): worth a listen.
  final Set<String> stressGuessed;

  /// How many words each tier answered.
  final Map<Source, int> sourceCounts;

  /// True when nothing was left unresolved, dropped or unsupported.
  bool get isClean =>
      unresolved.isEmpty && droppedChars.isEmpty && unsupportedMarkup.isEmpty;
}

/// Sentence in, Kokoro phoneme string out.
///
/// Order per word: inline `[word](/ipa/)` override, glossary respelling or replacement, lexicon
/// (with a POS cue for heteronyms), morphology on lexicon stems, letter-to-sound rules, and
/// finally "unresolved", which is reported and spoken as nothing.
class Phonemizer {
  Phonemizer({
    required this.lexicon,
    required this.rules,
    required this.respellingRules,
    required this.mapper,
    Map<String, String> glossary = const {},
    this.reductions = const Reductions(),
  }) : glossary = Map.unmodifiable(glossary),
       _respelling = Respelling(respellingRules) {
    _engine = RuleEngine(rules, finish: const Finisher().call);
    _pipeline = WordPipeline([LexiconResolver(lexicon), MorphResolver(lexicon), _engine]);
    final keys = glossary.keys.where((k) => k.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    _glossaryRe = keys.isEmpty
        ? null
        : RegExp(
            '(?<![\\p{L}\\p{N}])(?:${keys.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}])',
            unicode: true,
          );
  }

  /// Builds a phonemizer from the contents of the bundled assets (so Flutter apps can pass the
  /// asset strings) and the Kokoro `config.json`.
  factory Phonemizer.fromTexts({
    required String lexiconText,
    required String rulesText,
    required String respellingRulesText,
    required String kokoroConfigJson,
    Map<String, String> glossary = const {},
    Reductions reductions = const Reductions(),
  }) => Phonemizer(
    lexicon: Lexicon.parse(lexiconText),
    rules: RuleParser().parse(rulesText),
    respellingRules: RuleParser().parse('$respellingRulesText\n$rulesText'),
    mapper: KokoroMapper(KokoroVocab.fromConfigJson(kokoroConfigJson)),
    glossary: glossary,
    reductions: reductions,
  );

  /// Reads `en_lexicon.txt`, `en_us.rules` and `en_respell.rules` from [assetsDir] and the vocab
  /// from [kokoroConfigPath]. For tools, tests and desktop builds.
  factory Phonemizer.fromDirectory(
    String assetsDir, {
    required String kokoroConfigPath,
    Map<String, String> glossary = const {},
    Reductions reductions = const Reductions(),
  }) {
    String read(String name) => File('$assetsDir/$name').readAsStringSync();
    return Phonemizer.fromTexts(
      lexiconText: read('en_lexicon.txt'),
      rulesText: read('en_us.rules'),
      respellingRulesText: read('en_respell.rules'),
      kokoroConfigJson: File(kokoroConfigPath).readAsStringSync(),
      glossary: glossary,
      reductions: reductions,
    );
  }

  final Lexicon lexicon;
  final RuleSet rules;

  /// `en_respell.rules` followed by `en_us.rules`.
  final RuleSet respellingRules;
  final KokoroMapper mapper;

  /// Whole-word, case-sensitive replacements, as in `glossaries/*.csv`.
  final Map<String, String> glossary;
  final Reductions reductions;

  final Respelling _respelling;
  late final RuleEngine _engine;
  late final WordPipeline _pipeline;
  late final RegExp? _glossaryRe;

  /// Rule line to hit count for the rule engine (see `assets/en_us.rules`).
  Map<int, int> get ruleHits => _engine.ruleHits;

  static final _token = RegExp(
    r"(?<word>\p{L}[\p{L}'’]*(?:-\p{L}[\p{L}'’]*)*)|(?<space>\s+)|(?<digit>\p{N}+)|(?<other>.)",
    unicode: true,
  );

  PhonemizeResult phonemize(String text) {
    final run = _Run();
    for (final seg in splitOverrides(text)) {
      switch (seg) {
        case PlainText():
          _plain(seg.text, run, useGlossary: true);
        case OverrideWord():
          final r = resolveOverride(seg, mapper);
          for (final d in r.dropped) {
            run.dropped.update(d, (n) => n + 1, ifAbsent: () => 1);
          }
          run.addWord(seg.word, r.phones);
        case UnsupportedMarkup():
          run.unsupported.add(seg.text);
      }
    }
    return run.finish(reductions, this);
  }

  void _plain(String text, _Run run, {required bool useGlossary}) {
    final re = _glossaryRe;
    if (!useGlossary || re == null) {
      _tokens(text, run);
      return;
    }
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start < last) continue;
      _tokens(text.substring(last, m.start), run);
      last = m.end;
      final key = m[0]!;
      final value = glossary[key]!;
      if (Respelling.looks(value)) {
        final w = _respelling.parse(value);
        if (w == null) {
          run.unresolve(value);
        } else {
          var phones = w.phones;
          // "Urza's": the possessive attaches to the respelled word
          final poss = RegExp(r"['’]s(?![\p{L}\p{N}])", unicode: true).matchAsPrefix(text, last);
          if (poss != null && phones.isNotEmpty) {
            phones = [
              ...phones,
              for (final s in MorphResolver.inflectionS(phones.last.symbol)) Phone(s),
            ];
            last = poss.end;
          }
          run.addWord(
            key,
            WordPhones(phones, w.source, stressGuessed: w.stressGuessed),
            respelling: w.stressGuessed ? value : null,
          );
        }
      } else if (value.isNotEmpty) {
        _plain(value, run, useGlossary: false); // one pass, like the Python tools
      }
    }
    _tokens(text.substring(last), run);
  }

  void _tokens(String text, _Run run) {
    for (final m in _token.allMatches(text)) {
      if (m.namedGroup('word') != null) {
        _word(m.namedGroup('word')!, run);
      } else if (m.namedGroup('space') != null) {
        run.addSpace();
      } else {
        final ch = m[0]!;
        if (mapper.vocab.contains(ch)) {
          run.addPunct(ch);
        } else if (ch == '–' || ch == '―') {
          run.addPunct('—');
        } else {
          run.dropped.update(ch, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
  }

  void _word(String token, _Run run) {
    final cleaned = token.replaceAll('’', "'");
    var first = true;
    for (final piece in cleaned.split('-')) {
      final word = piece.replaceAll(RegExp(r"^'+|'+$"), '');
      if (word.isEmpty) continue;
      if (!first) run.addSpace(); // a hyphenated word is spoken as its parts
      first = false;
      final pos = posCue(run.previousWord);
      final cued = pos == null ? null : lexicon.lookup(word, pos: pos);
      final WordPhones result;
      if (cued != null && cued != lexicon.lookup(word)) {
        result = WordPhones(parsePhones(cued), Source.lexicon);
      } else {
        result = _pipeline.phonemize(word);
      }
      if (result.source == Source.unresolved) {
        run.unresolve(word);
      } else {
        run.addWord(word, result);
      }
    }
  }
}

sealed class _Item {}

class _Word extends _Item {
  _Word(this.text, this.phones, this.source);
  final String text;
  List<Phone> phones;
  final Source source;
}

class _Space extends _Item {}

class _Punct extends _Item {
  _Punct(this.ch);
  final String ch;
}

class _Run {
  final items = <_Item>[];
  final unresolved = <String, int>{};
  final dropped = <String, int>{};
  final unsupported = <String>[];
  final stressGuessed = <String>{};
  final sourceCounts = <Source, int>{};
  String? previousWord;

  void addWord(String text, WordPhones w, {String? respelling}) {
    items.add(_Word(text, [...w.phones], w.source));
    sourceCounts.update(w.source, (n) => n + 1, ifAbsent: () => 1);
    if (respelling != null) stressGuessed.add(respelling);
    previousWord = text;
  }

  void addSpace() => items.add(_Space());
  void addPunct(String ch) {
    items.add(_Punct(ch));
    previousWord = null;
  }

  void unresolve(String word) {
    unresolved.update(word, (n) => n + 1, ifAbsent: () => 1);
    sourceCounts.update(Source.unresolved, (n) => n + 1, ifAbsent: () => 1);
    previousWord = null;
  }

  PhonemizeResult finish(Reductions reductions, Phonemizer p) {
    final words = <SentenceWord>[];
    final byItem = <_Word, SentenceWord>{};
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it is! _Word) continue;
      var paused = true;
      for (var j = i + 1; j < items.length; j++) {
        if (items[j] is _Space) continue;
        paused = items[j] is! _Word;
        break;
      }
      final w = SentenceWord(
        it.text,
        it.phones,
        fromRules: it.source == Source.rules,
        pausedAfter: paused,
      );
      words.add(w);
      byItem[it] = w;
    }
    reductions.apply(words);

    final sb = StringBuffer();
    for (final it in items) {
      switch (it) {
        case _Word():
          sb.write(renderPhones(byItem[it]!.phones));
        case _Space():
          sb.write(' ');
        case _Punct():
          sb.write(it.ch);
      }
    }
    final mapped = p.mapper.restrict(sb.toString().replaceAll(RegExp(r' {2,}'), ' ').trim());
    for (final d in mapped.dropped) {
      dropped.update(d, (n) => n + 1, ifAbsent: () => 1);
    }
    return PhonemizeResult(
      phonemes: mapped.text,
      unresolved: unresolved,
      droppedChars: dropped,
      unsupportedMarkup: unsupported,
      stressGuessed: stressGuessed,
      sourceCounts: sourceCounts,
    );
  }
}
