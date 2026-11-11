# Handoff: pure-Dart English phonemizer (`bardoro_g2p`)

Context transferred from a design chat into this repo so Claude Code can continue. **Everything code-shaped in this file is an uncompiled sketch.** None of it has been run through `dart analyze` or `dart test`. Treat it as a starting point and expect fixes, especially in the rule parser and `RuleEngine`.

## Status log (newest last)

**Step 0 (scaffold): done.** `packages/bardoro_g2p` exists, is in the root `workspace:` list, `dart analyze`/`dart test` green. Environment note: the cloud container has no Flutter SDK, so `dart pub get` fails on the full workspace. Verification used a scratch wrapper that temporarily trimmed the root `workspace:` list and restored `pubspec.yaml`/`pubspec.lock` afterwards; run the usual `flutter pub get` locally.

**Step 1 (lexicon, mapper, vocab test): done.**
- Vocab verified against the real `hexgrad/Kokoro-82M` `config.json` (supplied by the user because huggingface.co is blocked from the cloud container). It has **114** symbols; `test/fixtures/kokoro_config.json` keeps only `n_token` and `vocab` from it.
- **Diphthong claim confirmed:** `A I O W Y` are single vocab symbols (A=eɪ, I=aɪ, O=oʊ, W=aʊ, Y=ɔɪ); the vocab also has `Q S T` which we do not use. There is no `eɪ`-style multi-character token.
- **Changed from the sketch:** internal phones are already Kokoro/misaki-US symbols (one code unit each), so lexicon, rules and stress share the model's alphabet. `KokoroMapper.fromIpa` exists only for external generic IPA (inline overrides, espeak oracle); `restrict` drops and reports anything outside the vocab. Phone symbols in the rule DSL (see below) must therefore be written in this alphabet, not generic IPA (`A` not `eɪ`, `ʧ` not `tʃ`).
- Lexicon: misaki `us_gold` + `us_silver` (Apache-2.0 repo, user-approved), 183,561 entries (4.6 MB text) with POS variants for heteronyms (`read`, `wind`, `live`...). Lookup is exact-case first, then lower-case; lower case is never promoted to a capitalised name.
- Tests assert no lexicon symbol and no internal phone is missing from the vocab.
- **Open:** misaki does not document the upstream origin of its entries; only the repo-level Apache-2.0 was verified (`assets/NOTICE`).

**Step 2 (rule DSL parser, RuleEngine, goldens): done.** Files: `lib/src/rules/rule_parser.dart`, `rule_engine.dart`, `lib/src/word_pipeline.dart` (types and `LexiconResolver`), `assets/en_us.rules` (150 rules), `test/golden/rules_golden.txt` (one `# --- section` per rule-file section), `test/rules_test.dart`.
- **Fixed from the sketch:** `RuleSet` is now immutable and built without mutating its input (stable ordering via explicit file position; a test checks the input list is untouched and candidate lists are unmodifiable). Anchors: `^` is only legal in the left context and `$` only in the right (parse error otherwise); left contexts compile to `(?:...)$` against the text before the grapheme, right contexts are matched with `matchAsPrefix` at the grapheme's end, so there is no per-rule substring of the tail. Classes expand to `[chars]`; `@NAME` is resolved per whitespace-separated token. The parser rejects output phones that are not in `phoneInventory`, unknown classes, and misplaced anchors, all with line numbers. The placeholder `(a) @C+ $ => æ` rule was dropped; the real rule file replaces the illustrative `(e)`/`(a)` fallbacks.
- **Rules are written in the Kokoro alphabet** (see step 1), and `ə l` etc. are explicit tokens. The engine returns raw phones; stress and reduction are plugged in through `RuleEngine(finish: ...)` (default adds no stress), which step 3 supplies.
- **Case:** the pipeline now passes tiers the word as written and caches on that key; the lexicon tries exact case then lower case, the rule engine lower-cases. Respelling resolution (step 4) will be case-sensitive by design (see open decisions).
- **Dead-rule test:** `no dead rules` fails if any rule is not hit by a golden word, so every rule has at least one frozen example. The golden file freezes behaviour; it is not ground truth. Known heuristic misses that are accepted because real words come from the lexicon: `house` (z), `finger` (ʤ), `cow` (O), `they` (θ).
- **Bug found by review of the first run:** `(er)` followed by `(r)` produced a doubled `ɹ` in `berry`; added `(arr) (err) (irr) (orr) (urr)`.
- **Speed:** 60,000 words in about 130 ms (JIT, uncompiled-to-AOT), so the O(n^2) concern is closed.

**Step 3 (Syllabifier, StressAssigner, MorphResolver): done.** Files: `lib/src/syllables.dart`, `stress.dart`, `morphology.dart`, tests `test/syllables_test.dart`, `test/stress_morph_test.dart`.
- **Syllabifier:** every vowel symbol is a nucleus (diphthongs are single symbols, so hiatus like `ɪ.di.ə` works); between nuclei the longest legal English onset goes to the next syllable (maximal onset; `ŋ` never starts a syllable, `tl dl θl` and 3-clusters other than s+stop+liquid/glide are illegal). Pure maximal onset on purpose: it keeps syllables light so the Latin stress rule prefers the antepenult for names (Aragorn, Alaric), which matches English. A lax-vowel closure variant was tried on paper and rejected for that reason.
- **StressAssigner:** `Finisher` plugs into `RuleEngine(finish: const Finisher().call)`. Suffix table (`-ation -ic -ical -ity -ion -ian -ial -ious -eous -ify`, final stress for `-eer -ese -esque`) counted in syllables from the end; else 1-2 syllables initial; 3+ heavy penult else antepenult; secondary stress two syllables before the primary; unstressed `æ ɑ ɔ ɛ ʌ ʊ ɜ` reduce to `ə`, while `ɪ`, diphthongs, `i`, `u` keep their quality. Not yet done: secondary stress after the primary, stress-neutral suffix handling inside rule-engine words (compounds), and `ɪ` to `ᵻ` reduction.
- **MorphResolver:** composes lexicon stems with `-s/-es/'s`, `-ed`, `-ing`, `-er/-est`, `-ly`, `-ness/-less/-ful/-ment` using the lexicon's own conventions (`ᵻz`, `ᵻd`, `ɪŋ`, `əɹ`, `ᵊl`, checked against the data). Handles silent e, doubled consonants and `y` to `i`. It only composes stems that exist in the lexicon and needs a stem of 3+ letters, so it never guesses. **Not done:** compound splitting (e.g. `Ironwood`), which the original requirements list; it is left open because a wrong split is a silent guess.
- **Rule changes made while reviewing real output:** dropped the broad `(a) @C @V => A` rule (it made `Aragorn` read `æˈɹAɡɔɹn`; open-syllable a is a coin flip for names), kept narrow `(a) tion $` and `(a) ture $`; added `(ar|er|ir) @V` (`Sarah`, `Aragorn`, `Tarin` now use `æɹ`).
- **Pipeline order** `[LexiconResolver, MorphResolver, RuleEngine]` is tested, including `unresolved` reporting for a word with a non-ASCII letter (`Zü`): the rules deliberately refuse letters they have no rule for. Accented letters are still an open decision.

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
- The sketch's known issues were resolved in step 2 (see status log). The authoritative syntax description is the doc comment on `RuleParser`; phones are in the Kokoro alphabet, not generic IPA.

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
