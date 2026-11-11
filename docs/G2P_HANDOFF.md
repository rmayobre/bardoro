# Handoff: pure-Dart English phonemizer (`bardoro_g2p`)

Context transferred from a design chat into this repo so Claude Code can continue. **Everything code-shaped in this file is an uncompiled sketch.** None of it has been run through `dart analyze` or `dart test`. Treat it as a starting point and expect fixes, especially in the rule parser and `RuleEngine`.

## Goal

Build our own English grapheme-to-phoneme (G2P) engine in Dart, aiming for espeak-ng-like outcomes on out-of-vocabulary words (invented names and Bardoro respellings such as `Er-zuh`), for the embedded Kokoro engine (`packages/bardoro_kokoro_local`, see `docs/FLUTTER_CONVERSION.md` §6.5b.3 and decision D11). English only. The project is GPL-3.0-or-later (D14), so GPL data (espeak-ng's `en_list`/`en_rules`) may be used as a reference.

espeak-ng stays the planned bundled fallback and the **test oracle** (spike S5 in `docs/SPIKES.md`). This package is meant to reduce how often we need it and to handle respellings deterministically.

## Requirements (what espeak-like behavior needs)

1. **Pronunciation lexicon** (word to phonemes with stress). Candidates: CMUdict (~134k words), misaki gold/silver US dictionaries (Apache-2.0), espeak-ng `en_list` (GPL). Plus a small heteronym table (read, lead, live, wind) keyed on simple cues.
2. **Letter-to-sound rule engine**: ordered, context-sensitive rewrite rules, longest grapheme first, then file order. Expect a few hundred rules. espeak's `en_rules` is the structural reference.
3. **Morphology and syllabification**: suffix stripping (-s, -ed, -ing, -er, -ly) with allomorphs (/s z ɪz/, /t d ɪd/), compound splitting, a syllabifier (maximal onset plus sonority).
4. **Stress assignment for unknown words**: suffix-driven (-ic, -ity, -ation), penultimate/heavy-syllable heuristic, schwa reduction of unstressed vowels. This dominates how natural invented names sound.
5. **Sentence-level pass**: function-word reduction, "the" before vowels, optional American allophony (flapping), punctuation passed through (Kokoro uses it for prosody). Text normalization (numbers, abbreviations) sits in front, see §6.5b.4.

Alternative worth evaluating after the rules baseline: train a small G2P model offline on the lexicon (aligned pairs plus a decision tree or small net), export as a tiny asset, run in pure Dart as another `WordResolver` after the rules. Keep the rule engine for respellings and overrides.

## Bardoro-specific constraints

- **Respellings are pseudo-words.** Glossary values like `Er-zuh` need a dedicated resolver: split on `-`, treat each piece as one syllable, primary stress from capitalization (exact convention is an open decision), small piece-level rule table. Inline overrides `[word](/ipa/)` are checked before everything.
- **Output must match Kokoro's vocabulary, not generic IPA.** Map internal phones to the 114-symbol vocab in `hexgrad/Kokoro-82M` `config.json`. Misaki's US set reportedly uses single-character diphthongs (A, I, O, W, Y); this is unverified, so check against the vocab. Symbols missing from the vocab must be reported, and a test should assert none are dropped.
- Per `AGENTS.md`: never invent a pronunciation for the user; unresolved words are reported, not guessed silently.

## Proposed package

New pure-Dart package `packages/bardoro_g2p` (no Flutter import). This repo uses a Dart pub workspace, so add `packages/bardoro_g2p` to the `workspace:` list in the root `pubspec.yaml`, set `resolution: workspace` and `sdk: ^3.12.2` in its pubspec (match `bardoro_core`), use `lints: ^6.0.0` and `test: ^1.25.0`, and put `// SPDX-License-Identifier: GPL-3.0-or-later` at the top of each source file. `bardoro_kokoro_local` then depends on it.

```
packages/bardoro_g2p/
  lib/
    bardoro_g2p.dart            // exports
    src/
      phonemizer.dart           // facade: sentence in, phoneme string out
      word_pipeline.dart        // tier chain
      overrides.dart            // [word](/ipa/) parser
      lexicon.dart              // Lexicon + loader
      morphology.dart           // suffix stripping + allomorphs
      rules/
        rule_parser.dart        // DSL text -> RuleSet
        rule_engine.dart        // applies rules to a word
      syllables.dart            // Syllabifier
      stress.dart               // StressAssigner
      respelling.dart           // "Er-zuh" path
      reductions.dart           // sentence-level pass
      kokoro_mapper.dart        // internal phones -> Kokoro vocab
  assets/ en_lexicon.txt, en_us.rules, heteronyms.txt
  test/
```

Tier order per word: overrides, respelling (glossary values only), lexicon, morphology, rules, then report unresolved.

## Core types (sketch, uncompiled)

```dart
enum Source { override, lexicon, morphology, rules, respelling, unresolved }

class Phone {
  const Phone(this.symbol, {this.stress = 0}); // stress: 0/1/2, vowels only
  final String symbol;
  final int stress;
  bool get isVowel => vowels.contains(symbol);
}

class WordPhones {
  const WordPhones(this.phones, this.source);
  final List<Phone> phones;
  final Source source;
}

/// One tier. Return null to pass the word to the next tier.
abstract interface class WordResolver {
  WordPhones? resolve(String word);
}

class WordPipeline {
  WordPipeline(this.tiers);
  final List<WordResolver> tiers;      // lexicon, morphology, rules
  final _cache = <String, WordPhones>{};
  final unresolved = <String, int>{};

  WordPhones phonemize(String word) =>
      _cache[word] ??= _run(word);

  WordPhones _run(String word) {
    for (final t in tiers) {
      final r = t.resolve(word.toLowerCase());
      if (r != null) return r;
    }
    unresolved.update(word, (n) => n + 1, ifAbsent: () => 1);
    return const WordPhones([], Source.unresolved);
  }
}

class Phonemizer {
  Phonemizer(this.words, this.overrides, this.reductions, this.mapper);
  PhonemizeResult phonemize(String text);   // phonemes + unresolved set + dropped chars
}
```

Note: `_cache` is keyed on the original-case word but resolution lowercases it. Decide whether case should matter (proper nouns) before finalizing.

## Rule DSL (sketch)

NRL-style `left (grapheme) right => phones`. Phones are space-separated tokens (so multi-character phones need no parsing tricks). Rules never write stress marks; `StressAssigner` adds them later.

```
# en_us.rules
class V = a e i o u y
class C = b c d f g h j k l m n p q r s t v w x z
class F = e i y            # front vowels

# --- c
(c) @F        => s
(ch)          => tʃ
(ck)          => k
(c)           => k

# --- a (specific rules first; first match wins within a grapheme length)
^ (a) @C e $              => eɪ     # "name"
(a) @C+ $                 => æ
(ai)                      => eɪ
(a)                       => ə

# --- word endings
(tion) $                  => ʃ ə n
@C (e) $                  =>        # silent e: empty output
(e)                       => ɛ
```

Syntax:
- `class NAME = chars` defines a single-character class; `@NAME` expands to `[chars]`.
- Contexts may use `^`, `$`, `?`, `*`, `+`, `|` and classes. No parenthesised groups, since the grapheme is the only `(...)`.
- Application order: longest grapheme first, then file order (so `(ch)` beats `(c)`, and specific contexts must precede general ones).
- `#` starts a comment; empty output means silent.
- Known sketch issues to resolve: the `(a) @C+ $ => æ` rule is a placeholder and not linguistically right; the `(e)` fallback to ɛ and `(a)` to ə are illustrative only. Phone symbols here are generic IPA and still need the Kokoro mapper.

## Parser and engine (sketch, uncompiled)

```dart
class Rule {
  Rule(this.grapheme, this.left, this.right, this.out, this.line);
  final String grapheme;
  final RegExp? left, right;
  final List<String> out;
  final int line;                       // for error messages and coverage stats

  bool matches(String w, int i) {
    if (!w.startsWith(grapheme, i)) return false;
    if (left != null && !left!.hasMatch(w.substring(0, i))) return false;
    if (right != null && !right!.hasMatch(w.substring(i + grapheme.length))) {
      return false;
    }
    return true;
  }
}

class RuleSet {
  RuleSet(List<Rule> rules) {
    for (final r in rules) {
      (_byFirst[r.grapheme[0]] ??= []).add(r);
    }
    for (final l in _byFirst.values) {
      // List.sort isn't guaranteed stable: keep file order explicitly.
      final indexed = l.asMap().entries.toList()
        ..sort((a, b) {
          final c = b.value.grapheme.length.compareTo(a.value.grapheme.length);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      l..clear()..addAll(indexed.map((e) => e.value));
    }
  }
  final _byFirst = <String, List<Rule>>{};
  Iterable<Rule> candidates(String ch) => _byFirst[ch] ?? const [];
}

class RuleEngine implements WordResolver {
  RuleEngine(this.rules, this.stress, this.syllabifier);
  final RuleSet rules;
  final StressAssigner stress;
  final Syllabifier syllabifier;
  final ruleHits = <int, int>{};         // line -> count, finds dead rules

  @override
  WordPhones? resolve(String w) {
    final raw = <String>[];
    var i = 0;
    while (i < w.length) {
      final hit = rules.candidates(w[i]).where((r) => r.matches(w, i)).firstOrNull;
      if (hit == null) return null;      // letter with no rule: let the pipeline report it
      ruleHits.update(hit.line, (n) => n + 1, ifAbsent: () => 1);
      raw.addAll(hit.out);
      i += hit.grapheme.length;
    }
    final syllables = syllabifier.split(raw);
    return WordPhones(stress.assign(syllables, w), Source.rules);
  }
}
```

Known issues to check: `RuleSet`'s constructor mutates lists while iterating `values` (clear then addAll on the same list the entries were derived from; verify it behaves); `substring` per rule per position is O(n^2) per word and fine for words but worth a benchmark; left context regexes need to compile as `(?:...)$` and right as `^(?:...)`, with `^`/`$` in the DSL translated to word-boundary anchors (the parser is not written yet, roughly 60 lines: split each line on `(`, `)` and `=>`, expand `@X`).

## Other components

- **StressAssigner.assign(syllables, word)**: suffix table (`-ic`, `-ity`, `-ation`...) fixes position; otherwise penultimate heuristic with heavy-syllable rule (long vowel or two consonants); then reduce unstressed vowels to schwa.
- **RespellingResolver**: runs before the rule engine, only for glossary values. Splits on `-`, one syllable per piece, stress from capitalization, small piece-level rule table.
- **MorphResolver**: strip suffix, look up stem, choose allomorph from the stem's final phone.
- **KokoroMapper**: table-driven symbol map; anything not in `config.json` vocab goes into `droppedChars`; test asserts it is empty.

## Testing plan

1. **Rule-coverage report**: `ruleHits` per DSL line over the real books, to find dead rules.
2. **Oracle diff against espeak-ng** on a held-out CMUdict slice, reporting phoneme error rate by rule line. Also compare against Kokoro-FastAPI `/dev/phonemize` if a server is available.
3. **DSL golden tests**: small word-to-phones cases per rule-file section so a rule edit that breaks an earlier case fails immediately.
4. **Metrics to track**: phoneme error rate vs dictionary and vs espeak, stress-position accuracy, weighted unresolved-word rate per book (target under 1%, per SPIKES S3).
5. **By ear**: A/B the Kokoro output; exact espeak phoneme parity matters less than sounding right.

## Suggested order of work

1. Scaffold the package, add it to the workspace, get `dart analyze` and an empty `dart test` green.
2. `Lexicon` loader plus `KokoroMapper` plus vocab test (common English works, unknowns reported).
3. DSL parser and `RuleEngine` with golden tests; fix the sketch issues above.
4. `Syllabifier`, `StressAssigner`, `MorphResolver`.
5. `RespellingResolver` and inline overrides.
6. Sentence-level reductions and the `Phonemizer` facade.
7. Oracle diff harness; decide whether a learned OOV model is worth adding.

## Open decisions

- Lexicon source and license (CMUdict vs misaki vs espeak `en_list`); check license before bundling, as for the dictionary in `FLUTTER_CONVERSION.md` D5.
- Stress/capitalization convention for respellings (`ER-zuh` vs `Er-zuh`).
- Whether resolution is case-sensitive for proper nouns.
- Unicode-aware letter handling for accented names (see §9 of the conversion guide).
- Where text normalization lives (this package or `bardoro_kokoro_local`).
