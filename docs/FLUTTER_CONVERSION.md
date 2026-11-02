# Bardoro → Flutter Desktop: Conversion Guide

A working plan for turning the Bardoro Python/Bash toolkit (epub → Kokoro TTS → chaptered `.m4b`) into a Flutter desktop app. It explains what each script does today, which behaviors must survive the port, the target architecture, and a phased path to get there.

Everything here is derived from the repo as it stands (`tools/*.py`, `tools/make-audiobook.sh`, `voices/`, `glossaries/`, `tests/`, `AGENTS.md`). Where a statement is a recommendation rather than something read from the code, it says so. Package names are suggestions to evaluate on pub.dev, not pinned choices.

**Revision 2: embedded Kokoro.** The app is now planned to run Kokoro **locally inside the app** (ONNX model + phonemizer), with no server, Docker or Python. §6.5 defines a `TtsEngine` interface (the old HTTP client becomes one engine), §6.5b covers the embedded engine, and §11 gains an early de-risking spike phase. The embedded-engine material rests on external documentation (model cards, package pages), listed with sources in Appendix F. **None of the embedded-engine code or package behavior has been run or tested**, so treat the spike phase as mandatory, not optional.

---

## 1. Goals, non-goals, definition of done

**Goals**

- Do everything the CLI does from a GUI: import an epub, preview the sections, find and fix pronunciations, pick a voice, convert, and get one `.m4b` with chapter markers.
- Keep the same guarantees: resumable, per-book pronunciation files, shared series glossaries, voice profiles.
- Replace the terminal-only review loop (`test_glossary.py` + `review_pronunciations.py` + `play_audio.py`) with an in-app Pronunciation Lab.
- Stay compatible with the CLI's on-disk workspace so both can operate on the same books during the migration.
- Run Kokoro **locally inside the app**: the ONNX model, a phonemizer and the voice packs, with no server, Docker or Python required (§6.5b).
- Be an **open and free project under GPL-3.0-or-later** (D14), which lets the app bundle espeak-ng.

**Non-goals (for v1)**

- Remote-only operation as the primary mode. A Kokoro-FastAPI server stays supported as an optional second engine (and as a test oracle for the embedded one), but the default is the embedded engine.
- Mobile targets. Desktop only (macOS, Windows, Linux).
- Re-implementing ffmpeg's audio processing in Dart.
- The Claude skill (`tools/skill/SKILL.md`). It drives the Python CLI and stays as it is. See §6.14.

**Done when** a user can go from an epub to a finished `.m4b` without touching a terminal or running a Kokoro server (ffmpeg aside until you decide to bundle it; espeak-ng is bundled, §6.5b.3), and a parity suite (§10) shows the Dart text pipeline producing the same sections, titles and chunks as the Python one on a set of real books.

---

## 2. What Bardoro does today

```
book.epub
   │  find_unknown_words.py      words not in an English dictionary  ──►  words.csv
   │                                                                         │ you fill in respellings
   ▼                                                                         ▼
epub_to_kokoro.py  ◄───────────────────────────  glossaries/<series>.csv + words.csv
   │  split into chapters → apply respellings → Kokoro server → ffmpeg deep-voice → chapter_XX.flac
   ▼
output/<slug>/<slug>.m4b   (one file, chapter markers)
```

### Script inventory

| Script | Lines | Role | Becomes in Flutter |
|---|---:|---|---|
| `tools/epub_to_kokoro.py` | 505 | Section extraction, text prep, Kokoro client, ffmpeg steps, job loop, logging, pronunciation loader | Most of `bardoro_core` (several classes) |
| `tools/find_unknown_words.py` | 121 | Lists words missing from an English dictionary → `words.csv` | `UnknownWordFinder` + "Words" step of the wizard |
| `tools/voice_profiles.py` | 189 | Voice settings, profile JSON load/validate/create, flag → profile → default resolution | `VoiceSettings`, `VoiceProfileRepository`, Voices screen |
| `tools/make-audiobook.sh` | 88 | Two-phase wrapper (find words, then convert) | The wizard flow itself |
| `tools/update_glossary.py` | 69 | Merge a book's or staging glossary into a series glossary | `GlossaryRepository.merge` + Glossaries screen |
| `tools/test_pronunciation.py` | 83 | Render a word as written vs. respelled | Pronunciation Lab (quick test) |
| `tools/test_glossary.py` | 185 | Render every glossary entry into one review file + index | Pronunciation Lab (batch render) |
| `tools/review_pronunciations.py` | 211 | A/B listening loop that writes decisions back to the glossary | Pronunciation Lab (review mode) |
| `tools/play_audio.py` | 149 | Cross-platform player with fallbacks | An audio-playback package (§6.9) |
| `tests/smoke_test.sh` + `fake_kokoro_server.py` | 182 + 36 | End-to-end check against a fake server | Dart integration test + fake server (§10) |

Data that ships in the repo: `voices/deep-narrator.json`, `voices/plain-onyx.json`, `glossaries/magic-the-gathering.csv`, `glossaries/warcraft.csv`.

---

## 3. Key decisions (with recommendations)

| # | Decision | Recommendation | Why |
|---|---|---|---|
| D1 | Code layout | Three packages in one repo: **`bardoro_core`** (pure Dart, no Flutter import), **`bardoro_kokoro_local`** (Flutter package holding the embedded engine), and **`bardoro_app`** (Flutter UI). | The whole pipeline is testable with `dart test`, parity-checkable against Python, and can ship a headless `bin/bardoro.dart` CLI. The embedded engine sits in its own package because the ONNX binding (`flutter_onnxruntime`) needs Flutter; core only sees the `TtsEngine` interface. The UI stays thin. |
| D2 | On-disk workspace | Keep the **exact same folder layout and file formats** as the CLI (§4.2). | Both tools can work on the same book. A half-converted book can be finished from either side. Easiest migration path. |
| D3 | Audio processing | **Shell out to `ffmpeg`/`ffprobe`** with `Process`, same filter chain as today. | The deep-voice effect is one ffmpeg filter graph and the `.m4b` chapter markers come from ffmpeg's metadata muxing. Re-implementing either in Dart is a project in itself. |
| D4 | EPUB parsing | Build a small reader on **`archive` + `xml` + `html`**; evaluate `epubx` first if you'd rather not. | The extractor depends on spine order, per-file TOC titles, image `alt` text, and heading vs. paragraph tags. A thin reader gives you exact control and matches ebooklib's behavior more predictably. |
| D5 | "Unknown word" detection | Bundle the **English word list that pyspellchecker uses** as an asset and do a `Set<String>` lookup. | There is no pyspellchecker equivalent in Dart, but the detection is only "is this word in the dictionary". I checked: `pyspellchecker` ships `en.json.gz` (a `{word: frequency}` JSON, 160,572 words). §6.4 has the export snippet. Check the data's license before redistributing it. |
| D6 | Audio playback | `media_kit`, `audioplayers`, or `just_audio` (+ `just_audio_media_kit` on Windows/Linux). | Needed for the Pronunciation Lab and an optional finished-book player. Verify desktop support and seeking for whichever you pick. |
| D7 | State management | One of Riverpod or Bloc, plus `go_router`. | Pipeline progress is a long-lived stream; both handle that well. Use whichever you already prefer. |
| D8 | Pronunciation file formats | Support `.csv`, `.json`, `.txt`. **Drop `.py`** unless you really need it. | The Python loader reads `PRONUNCIATIONS = {...}` via `ast.literal_eval`. Dart has no safe equivalent short of writing a small literal parser. The app writes CSV anyway. |
| D9 | TTS engine strategy | One **`TtsEngine` interface** with two implementations: `LocalOnnxEngine` (default) and `KokoroHttpEngine` (optional). Build the HTTP engine first, as a test oracle. | The runner, resume logic and ffmpeg steps don't care where a chunk's audio comes from. The HTTP engine is cheap, validates the whole pipeline early, and gives you reference audio and reference phonemes (`/dev/phonemize`) to check the embedded engine against. |
| D10 | ONNX binding | **`flutter_onnxruntime`** (all six platforms per its pub.dev page; MIT). Alternatives: `onnxruntime_v2`, or `dart:ffi` straight to the ONNX Runtime C API. | Its pub.dev page lists all six platforms and a recent release (1.9.0, bundling ONNX Runtime 1.28.x). `onnxruntime_v2` also lists the desktop platforms (last release about nine months before the page I saw). Spike S1 must prove whichever you pick with the Kokoro model on your three OSes. |
| D11 | Phonemizer (G2P) | **Tiered:** inline phoneme overrides → dictionary + rules G2P in Dart → **bundled espeak-ng fallback** → report whatever is still unresolved. See §6.5b.3. | Kokoro's own G2P (misaki) uses espeak-ng for out-of-dictionary words, which is exactly the invented-name case Bardoro exists for. With the project under GPL-3.0-or-later (D14) there is no licensing reason to leave it out. If it is missing or fails at runtime the engine drops to "report unresolved" instead of failing silently. |
| D12 | Model and voice delivery | **Download on first run** into the app's data folder (with progress and checksum), not bundled in the app package. Allow a user-supplied path. | The model is 92 MB to 326 MB depending on precision, so bundling bloats every build and update. |
| D13 | Model precision | Default to **fp32**; offer int8 as a "faster/smaller, lower fidelity" option. | `flutter_onnxruntime` lists fp16 as not yet complete on Linux/Windows. kokoro-onnx's own release notes put int8 at a spectral correlation of 0.916 versus fp32 (fp16 is 0.999), so audible differences are plausible; verify by ear. |
| D14 | License | **GPL-3.0-or-later** for the whole project (decided: open and free). | espeak-ng is GPL-3.0-or-later, so bundling it is straightforward under the same license. The Kokoro model and misaki (Apache-2.0) and ONNX Runtime and `flutter_onnxruntime` (MIT) are compatible with GPLv3. Check every dependency yourself, including the exact ffmpeg build; this isn't legal advice. See §8.1. |

---

## 4. Target architecture

### 4.1 Layers

```
┌───────────────────────────── bardoro_app (Flutter) ─────────────────────────────┐
│  Screens / widgets      Library · Wizard · Pronunciation Lab · Glossaries ·      │
│                         Voices · Settings                                        │
│  State (controllers)    PipelineController · WordsController · LabController ... │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │ depends on
┌───────────────────────────── bardoro_core (pure Dart) ──────────────────────────┐
│  pipeline/   PipelineRunner, PipelineEvent, VoiceSettingsGuard                   │
│  epub/       EpubReader, SectionExtractor, Section                               │
│  text/       StrayCleaner, PronunciationApplier, RomanNumerals, Chunker          │
│  words/      UnknownWordFinder, WordListLoader                                   │
│  glossary/   PronunciationTable, PronunciationFileIO, GlossaryMerger             │
│  voice/      VoiceSettings, VoiceProfile, VoiceResolver, ProfileRepository       │
│  tts/        TtsEngine (interface), KokoroHttpEngine, VoiceBlend parser          │
│  audio/      FfmpegService, FilterBuilder, ChapterMetadata, ConcatList           │
│  lab/        ClipRenderer, ReviewSession                                         │
│  workspace/  Workspace (paths), BookProject, SettingsStore                       │
└─────────────────────────────────────────────────────────────────────────────────┘
          │ HTTP                         │ Process                       │ dart:io
     Kokoro-FastAPI               ffmpeg / ffprobe                  workspace folder
```

Rule of thumb: nothing in `bardoro_core` imports `package:flutter`. Everything that touches the network, ffmpeg or the filesystem sits behind a small class you can fake in tests.

The embedded engine lives beside core, implements core's `TtsEngine`, and is injected by the app:

```
┌─────────────────────── bardoro_kokoro_local (Flutter package) ──────────────────┐
│  LocalOnnxEngine        implements TtsEngine                                     │
│  onnx/       KokoroSession (wraps flutter_onnxruntime), ModelManager (download)  │
│  g2p/        TextNormalizer, Phonemizer, PhonemeOverrides, EspeakFallback?       │
│  tokens/     KokoroTokenizer (vocab), UtteranceChunker                           │
│  voices/     VoiceBank (per-voice style packs), blending                         │
│  audio/      PcmToFlac (PCM -> ffmpeg stdin -> FLAC chunk)                       │
└──────────────────────────────────────────────────────────────────────────────────┘
        │ ONNX Runtime (native, fetched at build)      │ optional: espeak-ng binary/lib
```

### 4.2 Folder layout

Repo:

```
bardoro/
  packages/
    bardoro_core/
      lib/ …                       (per the layers above)
      bin/bardoro.dart             (optional headless CLI, handy for parity + CI)
      assets/dictionary/en_words.txt
      test/
    bardoro_kokoro_local/          (embedded engine; see §6.5b)
      lib/ …
      assets/g2p/                  (English pronunciation dictionaries, vocab config)
      test/
  apps/
    bardoro_app/
      lib/ …
      assets/seed/                 (starter voices/*.json and glossaries/*.csv, copied on first run)
  tools/                           (the existing Python tools; keep until parity is proven)
```

User workspace (chosen on first run, e.g. `~/Bardoro`). **Same layout as the CLI**, so the two stay interchangeable:

```
<workspace>/
  books/                              source epubs
  voices/<name>.json                  voice profiles
  glossaries/<series>.csv             shared pronunciations
  output/<slug>/
    words.csv                         this book's pronunciations
    <slug>.m4b                        the finished audiobook
    chapters/
      chapter_01.flac …               finished chapters (the resume marker)
      chapter_01_part_001.flac …      in-progress chunks (deleted after each chapter)
      chapter_01_list.txt             ffmpeg concat list for that chapter
      all_chapters.txt, chapters_meta.txt
      voice_settings.json             settings the book was started with
      convert.log
  output/pronunciation_tests/<glossary>/
    clips/ , clips/reviewed/ , manifest.json , review_results.json
```

### 4.3 Suggested dependencies

| Need | Package (evaluate) |
|---|---|
| HTTP | `http` (or `dio` if you want cancel tokens) |
| EPUB zip/XML/HTML | `archive`, `xml`, `html` (or `epubx`) |
| CSV | `csv` (or hand-roll; the files are trivial) |
| Paths and dirs | `path`, `path_provider` |
| File and folder pickers | `file_picker` |
| Audio playback | `media_kit` / `audioplayers` / `just_audio` |
| Window chrome | `window_manager` |
| ONNX inference (embedded engine) | `flutter_onnxruntime` (or `onnxruntime_v2`, or FFI to the ONNX Runtime C API) |
| Native interop for espeak-ng (optional) | `ffi` (or just `Process` and the `espeak-ng` executable) |
| Model download | `http`/`dio` streaming + a SHA-256 check (`crypto`) |
| State + routing | `flutter_riverpod` (or Bloc), `go_router` |
| Value classes | `freezed` + `json_serializable` (optional) |
| Tests | `test`, `flutter_test`, `shelf` (fake Kokoro), `mocktail` |

---

## 5. Domain model (Dart sketches)

```dart
/// One thing that gets read aloud: prologue, chapter, interlude, epilogue...
class Section {
  const Section({required this.index, required this.title, required this.text});
  final int index;     // 1-based; becomes chapter_XX.flac
  final String title;
  final String text;   // for image-titled chapters this already starts with "Title.\n"
}

/// Everything that shapes the sound. Mirrors voice_profiles.BUILTIN.
class VoiceSettings {
  const VoiceSettings({
    this.voice = 'am_onyx(4)+am_adam(1)',
    this.speed = 1.0,     // server-side; keep near 1.0
    this.pitch = 0.94,    // ffmpeg; <1 is deeper
    this.tempo = 0.90,    // final speaking speed
    this.bassDb = 4,
    this.fx = true,
  });
  final String voice;
  final double speed, pitch, tempo;
  final num bassDb;
  final bool fx;
}

/// A profile is a partial VoiceSettings: every key optional.
class VoiceProfile {
  const VoiceProfile({required this.name, this.description, this.voice, this.speed,
      this.pitch, this.tempo, this.bassDb, this.fx});
  final String name;
  final String? description, voice;
  final double? speed, pitch, tempo;
  final num? bassDb;
  final bool? fx;
}

/// word -> respelling. An empty respelling means "leave Kokoro's own pronunciation alone".
typedef PronunciationTable = Map<String, String>;

class WordCount {
  const WordCount(this.word, this.count);
  final String word;
  final int count;
}

class BookProject {
  const BookProject({required this.slug, required this.epubPath, required this.workspace});
  final String slug, epubPath;
  final Workspace workspace;
  // derived: wordsCsv, chaptersDir, m4bPath, voiceSettingsJson, logFile
}
```

---

## 6. Feature-by-feature conversion

Each subsection: what it does now, the behavior to preserve, the Dart design, and the traps.

### 6.1 EPUB section extraction (`extract_sections`)

**Today.** Opens the epub with `ebooklib` (`ignore_ncx=True`), walks the **spine in reading order**, and for each HTML/XHTML/HTM item:

1. Collects the text of every `h1`/`h2`/`h3`/`p`, each passed through `clean_stray` (§6.2). Drops empty ones. Empty section → skipped.
2. Looks at the first 200 characters (`head`):
   - matches `SKIP_RE` (contents, copyright, about the author, acknowledgments, dedication, also by, notes, praise, title page, cover, map, glossary, discussion) → skipped;
   - matches neither `INCLUDE_RE` (prologue, prelude, chapter, epilogue, interlude, introduction, foreword, preface, afterword, `part …`, `book …`) **nor** has at least `MIN_CHARS_OTHER = 3000` characters → skipped.
3. Chooses a title:
   - **First element is a heading:** title is the first sentence of the first paragraph (split at `[.!?:]` + whitespace), capped at 60 chars, trimmed of ` .:`. If that is just "Book I"/"Part 2" and the next element is also a heading of ≤ 60 chars, join them: `Book I: The Human Component`.
   - **No heading** (title is an image): use the epub's TOC title for that file name (with a trailing `-(...)`/`–(...)` suffix stripped); otherwise, if an image's `alt` text is a number, `Chapter <alt>`; otherwise continue the numbering (`Chapter N`, one more than the previous). The title is also **spoken**: the text becomes `"{title}.\n{text}"`.
   - ALL-CAPS titles are converted to title case.

**Preserve.** Spine order; the exact include/skip rules and thresholds (keep the three constants at the top of one file, as Python does); the "title is spoken when it was an image" rule; the `--list` preview (a pure function returning `List<Section>` with char counts).

**Dart design.**

```dart
class EpubReader {
  /// Opens the zip, reads META-INF/container.xml -> OPF -> manifest + spine,
  /// and the nav document (EPUB 3) for TOC titles.
  static Future<EpubBook> open(String path);
}

class SectionExtractor {
  List<Section> extract(EpubBook book);
}
```

Run extraction in `Isolate.run` so large books don't jank the UI.

**Traps.**

- ebooklib is called with `ignore_ncx: True`, so TOC titles come from the EPUB 3 `nav` document, not the legacy NCX. Check on your real books whether any rely on NCX-only TOCs. Falling back to the NCX when there's no nav is a safe improvement but a parity break; decide deliberately.
- Python's `get_text(" ", strip=True)` joins text nodes with spaces and strips each. `package:html`'s `element.text` does not, so normalize whitespace yourself and test against golden output.
- `str.title()` in Python has a quirk (`"DON'T".title()` is `"Don'T"`; I checked). Don't copy the quirk. Write a clean title-casing function and accept the tiny diff in the rare all-caps-with-apostrophe title.
- `re.split(pattern, s, maxsplit=1)` has no direct Dart equivalent. Use `firstMatch` and `substring`.
- Dart's `\w` and `\b` are ASCII-only. Python's are Unicode-aware. See §9.

### 6.2 Text preparation (`clean_stray`, pronunciations, Roman numerals, chunking)

Order of operations per chapter, as in `main()`: stray cleanup happens at extraction time, then **pronunciations → Roman numerals → chunking**. Keep that order: pronunciation entries must win over the Roman-numeral rule (`Menethil II` in a glossary beats the automatic "the Second").

**Stray text.** `STRAY_RE = \b(?:oceanofpdf(?:\.com)?)\b` (case-insensitive) is removed, whitespace collapsed, and a section with no word characters left becomes empty. Keep the regex in one constant so adding another site watermark is a one-line change.

**Applying pronunciations.** Whole-word, **case-sensitive**, **longest entry first**. Count hits per word for the end-of-run log line.

```dart
String applyPronunciations(String text, Map<String, String> table, [Map<String, int>? hits]) {
  if (table.isEmpty) return text;
  final words = table.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  // Unicode-aware boundaries; Dart's \b is ASCII-only (see §9).
  final re = RegExp(
    r'(?<![\p{L}\p{N}_])(?:' + words.map(RegExp.escape).join('|') + r')(?![\p{L}\p{N}_])',
    unicode: true,
  );
  return text.replaceAllMapped(re, (m) {
    final w = m[0]!;
    if (hits != null) hits[w] = (hits[w] ?? 0) + 1;
    return table[w]!;
  });
}
```

Compile the regex once per run, not once per chapter. Verify lookbehind works on all three desktop targets with a unit test.

**Roman numerals.** Only II–XX (a lone I, V or X is never touched). The rule is based on the single word before the numeral:

- word is in `part, book, chapter, act, volume, vol, section, appendix, phase, stage, level, episode, season, article, war, world war, class, type, tier` (case-insensitive) → cardinal: `Part II` → `Part two`;
- else word starts with a capital letter → ordinal: `Terenas Menethil II` → `Terenas Menethil the Second`;
- else unchanged.

```dart
const _ordinals = ['first','second','third','fourth','fifth','sixth','seventh','eighth','ninth','tenth',
  'eleventh','twelfth','thirteenth','fourteenth','fifteenth','sixteenth','seventeenth','eighteenth',
  'nineteenth','twentieth'];
const _cardinals = ['one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve',
  'thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen','twenty'];

final _roman = {
  for (final (i, r) in 'I II III IV V VI VII VIII IX X XI XII XIII XIV XV XVI XVII XVIII XIX XX'
      .split(' ').indexed)
    if (r.length > 1) r: i + 1,
};
final _romanAlt = (_roman.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');
final _romanAfterWord = RegExp("\\b([A-Za-z][\\w'’-]*)([ \\t]+)($_romanAlt)\\b");
```

A `--no-roman-numerals` toggle belongs in the voice/convert settings.

**Chunking.** `CHUNK_CHARS = 2500` characters per request, split at paragraph then sentence boundaries. Port it line for line:

```dart
List<String> chunkText(String text, {int limit = 2500}) {
  final chunks = <String>[];
  var cur = '';
  for (final para in text.split('\n')) {
    final pieces = para.length <= limit ? [para] : para.split(RegExp(r'(?<=[.!?])\s+'));
    for (final piece in pieces) {
      if (cur.isNotEmpty && cur.length + piece.length + 1 > limit) {
        chunks.add(cur);
        cur = '';
      }
      cur = cur.isNotEmpty ? '$cur\n$piece' : piece;
    }
    if (cur.isNotEmpty && cur.length > limit * 0.7) { // keep paragraph-ish boundaries
      chunks.add(cur);
      cur = '';
    }
  }
  if (cur.isNotEmpty) chunks.add(cur);
  return chunks;
}
```

Two notes. Python's `len` counts code points and Dart's `String.length` counts UTF-16 units, so for exact golden parity on text with emoji or other astral characters use `runes.length`. And a single sentence longer than the limit is never split (in Python either); consider a hard-split fallback as an improvement.

### 6.3 Pronunciation files and glossaries (`load_pronunciations`)

**Formats read today.**

| Extension | Shape |
|---|---|
| `.csv` | Header row with `word` and `pronunciation` columns (extra `count` column ignored). UTF-8 with optional BOM. Header names matched case-insensitively. |
| `.json` | `{"Urza": "Er-zuh"}` or `[{"word": …, "pronunciation": …}]` |
| `.py` | `PRONUNCIATIONS = {…}` parsed with `ast.literal_eval`, never executed (drop in Dart, D8) |
| `.txt` | `word = pronunciation` (or tab-separated), `#` comments |

**Semantics to preserve.**

- **Blank means "leave Kokoro alone."** Blank rows are skipped when applying. Glossaries keep them (`keepBlank: true`) to record "reviewed; Kokoro's own pronunciation is fine."
- **Precedence is order of application.** For a conversion, load glossaries in the order the user listed them, then the book's own `words.csv` last. Later wins. A blank entry in a later file **never cancels** an earlier respelling.
- Writing: `\n` line endings, glossary header `word,pronunciation`, rows sorted case-insensitively; `words.csv` header `word,count,pronunciation`.
- **Phoneme values.** A pronunciation value may be inline phoneme markup such as `[Urza](/ˈɜɹzə/)` (§6.5b.3, §6.5b.11). It is just text to the loader and to `applyPronunciations`, so no file-format change is needed.

```dart
class PronunciationFileIO {
  Future<PronunciationTable> load(File f, {bool keepBlank = false});
  Future<void> writeGlossary(File f, PronunciationTable t);   // sorted, \n endings
}

PronunciationTable layered(List<PronunciationTable> inOrder) =>
    {for (final t in inOrder) ...t};  // later wins; callers pass tables loaded WITHOUT blank rows
```

### 6.4 Unknown-word finder (`find_unknown_words.py`)

**Today.**

1. Read **every HTML document item** in the epub (not only the spine), take its text, remove stray text, normalize curly quotes to `'`, and treat hyphens/dashes as spaces.
2. Tokenize with `[A-Za-z]+(?:'[A-Za-z]+)*`. Reduce possessives (`Urza's` → `Urza`, `Orcs'` → `Orcs`). Skip tokens shorter than 3 characters or still containing an apostrophe.
3. Count by lowercase form; remember the most common surface form for display.
4. Keep words that are not in the extra `--known` list and that pyspellchecker reports as unknown.
5. Drop words seen fewer than `--min-count` (default 2). Sort by count descending.
6. Write `word,count,pronunciation` with a blank third column.

**Dart design.** `UnknownWordFinder.find(EpubBook, {int minCount = 2, Set<String> known})` returning `List<WordCount>`. Load the dictionary once into a `Set<String>` (lowercase).

Export the word list from the Python package once and commit it as an asset (verified to work: 160,572 entries, about 1.5 MB as plain text):

```bash
python - <<'EOF'
import gzip, json, pathlib, spellchecker
p = pathlib.Path(spellchecker.__file__).parent / "resources" / "en.json.gz"
words = json.load(gzip.open(p, "rt", encoding="utf-8"))   # {word: frequency}
out = pathlib.Path("packages/bardoro_core/assets/dictionary/en_words.txt")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(sorted(words)) + "\n", encoding="utf-8")
EOF
```

Check the dictionary data's license before bundling it in a distributed app.

**Traps and improvements.**

- The tokenizer is ASCII-only, so an accented name like `Rhûn` is split into fragments and effectively invisible. Using `\p{L}` in Dart fixes this but changes output versus Python. Decide on purpose, and note it in the parity suite.
- Python sorts `(count, word)` tuples with `reverse=True`, so ties come out in reverse alphabetical order. Irrelevant to correctness; matters only for a byte-exact diff.
- Run it in an isolate; a full novel is a few hundred thousand tokens.
- UI: show results in an editable table with a "known/ignore" action (the `--known` list becomes a persisted per-workspace ignore list). With the embedded engine, also flag words missing from the G2P dictionary (§6.5b.3): those are the words that need a respelling or phonemes, and they overlap with, but are not identical to, the spellchecker's unknown words.

### 6.5 TTS engines: the `TtsEngine` interface and the HTTP engine

The pipeline asks for one thing: "turn this chunk of text (up to about 2,500 characters) into one audio file." That is exactly what Kokoro-FastAPI does for the Python tool, which splits and stitches internally. Keep that contract and put both engines behind it:

```dart
abstract interface class TtsEngine {
  String get id;                       // 'local-onnx' | 'kokoro-http'
  /// Load the model or check the server. Throws with a user-readable reason.
  Future<void> prepare();
  /// Words the engine could not phonemize (local engine; always empty for HTTP).
  Set<String> get unresolvedWords;
  /// Turn one chunk of text into a FLAC file at [dest].
  Future<void> synthesizeToFile({
    required String text,
    required VoiceSettings voice,
    required File dest,
    void Function(String message)? onLog,
  });
  Future<void> dispose();
}
```

`PipelineRunner` (§6.7) takes a `TtsEngine`, so resume, logging, ETA and the ffmpeg steps are identical for both engines. Chunk files stay FLAC, so the concat step doesn't change. The embedded engine is §6.5b; the rest of this section is the HTTP engine, which you should build first because it validates the pipeline and later serves as the reference for the embedded one (D9).

#### HTTP engine (optional; also your test oracle)

**HTTP contract** (also in Appendix A):

```
POST {baseUrl}/v1/audio/speech
Content-Type: application/json
{"model": "kokoro", "input": "<chunk text>", "voice": "<voice or blend>",
 "response_format": "flac", "speed": 1.0}
→ 200 with FLAC bytes
```

**Behavior to preserve.**

- Per-request timeout **900 s**; up to **3 attempts**; wait `3 × attempt` seconds between attempts (3 s, then 6 s); every failure is logged with attempt number.
- A response is a success only if status is 200 **and** the body is non-empty.
- If the error text indicates a voice problem (`voice` plus `not found` or `invalid`), **abort immediately** with the hint "try a plain voice such as `am_onyx` (no blend syntax)". The blend syntax `am_onyx(4)+am_adam(1)` is a Kokoro-FastAPI feature, passed through verbatim in `voice`.
- After the last failed attempt, abort the whole run with a clear message. The run is resumable, so nothing is lost.
- **No hardcoded server URL** (an `AGENTS.md` rule). The CLI falls back to `KOKORO_URL`, then `http://localhost:8880`; in the app, make the URL a first-run setting and validate it with a "Test connection" button. (The skill file uses `GET /v1/audio/voices` as a reachability check; confirm the response shape against your server before building a voice picker on it.)

```dart
/// Low-level client. `KokoroHttpEngine.synthesizeToFile` calls this and writes the returned bytes to `dest`.
class KokoroHttpClient {
  KokoroHttpClient(String baseUrl, {http.Client? client})
      : _base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();
  final String _base;
  final http.Client _http;

  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    required double speed,
    int retries = 3,
    void Function(String message)? onLog,
  }) async {
    final uri = Uri.parse('$_base/v1/audio/speech');
    final body = jsonEncode({
      'model': 'kokoro', 'input': text, 'voice': voice,
      'response_format': 'flac', 'speed': speed,
    });
    for (var attempt = 1; attempt <= retries; attempt++) {
      String err;
      try {
        final r = await _http
            .post(uri, headers: {'content-type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 900));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
        err = 'HTTP ${r.statusCode}: ${_clip(r.body, 300)}';
      } on Exception catch (e) {
        err = '$e';
      }
      onLog?.call('attempt $attempt/$retries failed: $err');
      final low = err.toLowerCase();
      if (low.contains('voice') && (low.contains('not found') || low.contains('invalid'))) {
        throw KokoroVoiceRejected(err);
      }
      if (attempt < retries) await Future<void>.delayed(Duration(seconds: 3 * attempt));
    }
    throw KokoroUnavailable('Giving up on a chunk after $retries attempts');
  }
}
```

For cancellation, use `dio`'s `CancelToken` or close the client; the runner should check a cancel flag between chunks either way.

### 6.5b The embedded engine (`LocalOnnxEngine`)

Everything in this subsection is based on external documentation (Appendix F), not on running the code. Spikes S1 to S5 in §11 exist to confirm it; the step-by-step checklist is in `SPIKES.md`.

#### 6.5b.1 What the server does that the app must now do itself

| Kokoro-FastAPI does (per its README and the model cards) | The embedded engine needs |
|---|---|
| Normalizes input text (numbers, symbols and so on; it can be switched off per request) | `TextNormalizer` (§6.5b.4) |
| Converts text to phonemes with misaki: dictionaries and rules, with espeak-ng as the fallback for unknown words; honors inline `[word](/phonemes/)` | `Phonemizer` (§6.5b.3) |
| Maps phoneme characters to token ids using the model's vocabulary | `KokoroTokenizer` |
| Splits long text at sentence boundaries into token-limited chunks (defaults: target 175 to 250 tokens, absolute max 450; the model accepts at most 510) and stitches the audio | `UtteranceChunker` plus PCM stitching |
| Loads voice packs and blends them (`am_onyx(4)+am_adam(1)`; ratios are normalized to 100%) | `VoiceBank` |
| Runs the model | `KokoroSession` on ONNX Runtime |
| Encodes FLAC | `PcmToFlac` via ffmpeg |

Flow for one chunk of text:

```
chunk (≤ ~2500 chars, from chunkText)
  → normalize → split into sentences
  → phonemize each sentence: inline overrides → dictionary + rules → fallback      [unresolved words collected]
  → tokenize (vocab) → group sentences into utterances of ≤ ~250 tokens (never more than 510)
  → per utterance: style = pack[tokenCount]; run model (ids padded with 0 at both ends, style, speed)
  → float32 PCM @ 24 kHz → join with short silences → ffmpeg → chunk .flac
```

#### 6.5b.2 Model files and tensor contract

- **Model:** Kokoro-82M v1.0 as ONNX, Apache-2.0. The onnx-community repo lists `model.onnx` (fp32, 326 MB), `model_fp16.onnx` (163 MB), `model_quantized.onnx` (92.4 MB) and several mixed or 4-bit variants. kokoro-onnx's releases list `kokoro-v1.0.onnx` (326 MB), an fp16 file (164 MB) and an int8 file (114 MB).
- **Inputs:** the model card names the token input `input_ids`; **the kokoro-onnx `kokoro-v1.0.onnx` file I inspected names it `tokens`** (int64, shape `(1, N)`, N ≤ 512, padded with token `0` at both ends, so at most 510 real tokens); `style` float32 `(1, 256)`; `speed` float32 `(1,)`. **Output:** `audio`, a float32 1-D waveform at 24,000 Hz. Always read the names from `session.getInputNames()` instead of hard-coding them.
- **Verified on the v1.0 file (325,532,387 bytes, SHA-256 `7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5`):** `tokens` int64, `speed` float32. Other exports differ (the v1.1-zh file uses an int `speed`), so check dtypes per file. Download: `https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx`.
- **Voices:** each voice is a table of 256-float style rows indexed by the number of tokens: the model card's reference code reshapes the file to `(-1, 1, 256)` and takes `voices[len(tokens)]`, whereas kokoro-onnx 0.6.1 takes row `min(len(tokens), rows) - 1` (one lower, tokens counted before the 0 padding). The difference is one row of 510; spike S1 checks it by ear. Two distributions exist: raw float32 `.bin` files per voice (onnx-community; read straight into a `Float32List`; check the repo's `voices/` folder for what is actually there) and kokoro-onnx's `voices-v1.0.bin`, an npz archive of 54 voices, every one shaped `(510, 1, 256)` (28,214,398 bytes, SHA-256 `bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d`, same release URL with `voices-v1.0.bin`; `am_onyx` and `am_adam` are present) (a zip of `.npy` arrays: parse with `archive` plus a small `.npy` reader, or convert once). Prefer the raw files.
- **Vocabulary:** the phoneme-character → id map comes from `config.json` in `hexgrad/Kokoro-82M`. Decide how to treat characters missing from the vocab (typical implementations drop them); log them either way.
- **Speed:** keep it at 1.0 and slow delivery with ffmpeg `tempo`, as the CLI does today (`AGENTS.md`).

#### 6.5b.3 The phonemizer: do you need espeak-ng?

**Short answer:** to match what the server does today for invented names, you need espeak-ng or an equivalent fallback. Because the project is GPL-3.0-or-later (D14), **bundle espeak-ng**.

**Why.** misaki's English G2P is dictionaries plus rules; **out-of-dictionary words go to an espeak-ng fallback** (its README: you build an `EspeakFallback` and pass it in; passing `None` disables it; a non-espeak fallback is only a TODO). Invented names like Urza are exactly those words. And Bardoro's respellings such as `Er-zuh` are pseudo-words too, so **they depend on the same fallback**. Without any fallback they come back unresolved.

| Tier | What it is | Good | Costs |
|---|---|---|---|
| 1. Dictionary + rules in Dart | Port misaki's English pipeline using its dictionaries (the Rust port `voice-g2p`, MIT, reports about 90k "gold" and 93k "silver" entries; misaki itself is Apache-2.0), or start from the Dart package `malsami` (MIT, English only, dictionary-based; its page lists "no neural network fallback for out-of-vocabulary words yet"; v0.0.3, unverified uploader) | Pure Dart, no native dependencies, fast | Common English only; unknown words stay unresolved |
| 2. Phoneme overrides | Glossary values as inline markup `[Urza](/ˈɜɹzə/)`. misaki, Kokoro-FastAPI and malsami all use this syntax | Exact and deterministic; no espeak at conversion time; also works with the HTTP engine and the CLI, since the value is just text | Someone has to write the phonemes; the Lab can help (below) |
| 3. espeak-ng fallback | Call `espeak-ng` per unknown word (`-q --ipa -v en-us`; check the flags for your version), then map its IPA to Kokoro's phoneme set (misaki has an espeak → misaki mapping to port) | Same behavior as the server for unknown words, respellings included | Bundled per OS; GPL-3.0-or-later (fine for this project, D14); an IPA → Kokoro mapping to port |
| 4. Report unresolved | The engine records words it could not phonemize; the wizard warns or blocks until the user adds a respelling or phonemes | Honest; no silent mispronunciation | More work for the user |

**Recommendation (GPL project).** Ship all four tiers, resolving each word in this order: inline overrides → dictionary + rules → bundled espeak-ng → report as unresolved. Details:

- **Call it as a subprocess first** (`espeak-ng` executable plus its `espeak-ng-data` directory). It is simple and crash-isolated; both are licence-fine here. Move to FFI against `libespeak-ng` only if spike S5 shows process spawning is too slow.
- **Batch and cache.** Collect a chapter's unresolved words, phonemize each unique word once, and cache the result per book (and per series, if you like). Respellings repeat thousands of times, so the cache matters more than call speed.
- **Port the mapping.** espeak-ng's IPA has to be converted to Kokoro's phoneme set. misaki has an espeak → misaki mapping; look in its espeak module and port it with tests.
- **Fail loudly.** If the bundled binary is missing or errors, fall back to "report unresolved" and tell the user, rather than silently dropping words.
- **Authoring help.** A Lab action "suggest phonemes for this respelling" uses the same path to fill in tier-2 entries, so a finished glossary also works without espeak, for example on the HTTP engine.
- **Per-OS builds.** Windows binaries are published on espeak-ng's releases page; on macOS and Linux build it (or package it via Flatpak/AppImage/Homebrew formula) and ship a matching data directory. Version the binary and data together.

**Licensing.** The espeak-ng repository states GPL version 3 or later, and its page says nothing about linking or embedding. With Bardoro itself released under GPL-3.0-or-later (D14), bundling the binary or linking the library is consistent with that license. You still have obligations: ship the license text and notices, and provide the corresponding source for binaries you distribute (§8.1). Not legal advice.

#### 6.5b.4 Text normalization (a gap the server used to hide)

Kokoro-FastAPI normalizes input text by default (its README says it can be switched off per request). Numbers, currency, abbreviations such as "Dr.", times and unusual quote or dash characters need handling, or they may be skipped or garbled. The Python CLI never did this itself (other than Roman numerals). Scope it explicitly: start with numbers (cardinals, ordinals, years), common titles and abbreviations, currency, and quote/dash/ellipsis normalization; compare against the server's output on real chapters (D9's oracle).

#### 6.5b.5 Tokenizer and utterance chunker

```dart
class KokoroTokenizer {
  KokoroTokenizer(this.vocab);                  // phoneme character -> id, from config.json
  final Map<String, int> vocab;

  /// Phoneme string -> ids. Characters missing from the vocab are dropped and reported.
  List<int> encode(String phonemes, {void Function(String ch)? onMissing}) {
    final ids = <int>[];
    for (final rune in phonemes.runes) {
      final ch = String.fromCharCode(rune);
      final id = vocab[ch];
      if (id == null) { onMissing?.call(ch); continue; }
      ids.add(id);
    }
    return ids;
  }
}

/// The model expects a 0 at both ends. Callers guarantee ids.length <= 510.
List<int> padIds(List<int> ids) => [0, ...ids, 0];

/// Greedy grouping of sentences into utterances (defaults mirror Kokoro-FastAPI's documented targets).
/// splitIfTooLong is yours to write: split an over-long sentence at a space/comma, never exceeding absMax.
List<List<int>> groupUtterances(List<List<int>> sentences, {int target = 250, int absMax = 450}) {
  final out = <List<int>>[];
  var cur = <int>[];
  void flush() { if (cur.isNotEmpty) { out.add(cur); cur = <int>[]; } }
  for (final s in sentences) {
    for (final piece in splitIfTooLong(s, absMax)) {
      if (cur.isNotEmpty && cur.length + piece.length > target) flush();
      cur.addAll(piece);
    }
  }
  flush();
  return out;
}
```

Join sentences inside an utterance with the vocab's space token. Per-chunk resume is unchanged: this all happens inside `synthesizeToFile`.

#### 6.5b.6 Voice bank and blending

Blending is a weighted average of the voice packs, then the row for the token count is picked. Kokoro-FastAPI documents that ratios are normalized to sum to 100%.

```dart
class VoiceBank {
  VoiceBank(this._packs);                       // name -> Float32List (rows x 256)
  final Map<String, Float32List> _packs;

  /// "am_onyx(4)+am_adam(1)" or "af_bella". A missing weight means 1. Cache the result per spec.
  Float32List resolve(String spec) {
    final parts = parseBlend(spec);             // [(name, weight)]; throws on an unknown voice
    final total = parts.fold<double>(0, (s, p) => s + p.weight);
    final out = Float32List(_packs[parts.first.name]!.length);   // assumes all packs have equal length: verify
    for (final p in parts) {
      final pack = _packs[p.name]!;
      final w = p.weight / total;
      for (var i = 0; i < out.length; i++) { out[i] += pack[i] * w; }
    }
    return out;
  }

  Float32List styleFor(Float32List pack, int tokenCount) =>
      Float32List.sublistView(pack, tokenCount * 256, tokenCount * 256 + 256);
}
```

The blend syntax is the same one your profiles already use, so `deep-narrator.json` works unchanged. Check the result by ear against the server (it can also export a reference blended pack through its `/v1/audio/voices/combine` endpoint).

#### 6.5b.7 Inference and PCM output

```dart
abstract interface class KokoroSession {
  /// Runs the model once. Shapes: ids (1, N), style (1, 256), speed (1,).
  Future<Float32List> run({required List<int> inputIds, required Float32List style, required double speed});
}
```

Implement it over `flutter_onnxruntime` in `bardoro_kokoro_local`. I haven't verified that package's exact method names (its page confirms desktop support and execution-provider configuration), so write the adapter against its docs. Keeping this interface lets you swap in `onnxruntime_v2` or raw FFI without touching the engine.

Join the utterances' PCM with short silences. Start around 0.2 s and tune by ear; this is my suggestion, since Kokoro-FastAPI's README doesn't document how it joins segments. Then write the chunk file by piping raw PCM to ffmpeg:

```
ffmpeg -y -v error -f f32le -ar 24000 -ac 1 -i pipe:0 -c:a flac chapter_01_part_001.flac
```

Write `samples.buffer.asUint8List()` to the process's stdin (little-endian on all desktop targets). Everything downstream (chapter concat with the deep-voice filter, `.m4b` assembly) is unchanged; the filter probes the sample rate from the first chunk and will see 24 kHz.

#### 6.5b.8 Performance, acceleration, memory

- kokoro-onnx claims "near real-time performance on macOS M1" but its page gives no benchmark figures. Treat it as unverified. For a multi-hour audiobook, throughput is the make-or-break number: measure real-time factor on your hardware for fp32 and int8 in spike S2, on CPU first, then with execution providers.
- `flutter_onnxruntime` lists "EP configuration" on all platforms but its page doesn't say which providers (CoreML, DirectML, CUDA and so on) are available where. Verify per OS.
- Run inference off the UI isolate, create the session once per run and reuse it across chunks.
- One Android-focused package (`neural_tts`) quotes about 510 MB of RAM for its Kokoro setup. That's a different stack, so only indicative; measure yours.

#### 6.5b.9 Model delivery (`ModelManager`)

Store under the app's data folder, e.g. `kokoro/v1.0/{model file, config.json, voices/*.bin}`. Download with progress, resume and a SHA-256 check; pin exact file URLs and hashes once you've chosen a file set (I haven't verified download URLs). Offer "use my own files" for offline setups, show sizes before downloading, and let the user delete models. Include the model's credits in an About screen; the Kokoro-82M model card notes its training data includes CC BY audio (Koniwa, SIWIS), so follow upstream's attribution guidance.

#### 6.5b.10 Existing Dart/Flutter Kokoro packages (assessment)

| Package | What it is | Desktop? | Notes |
|---|---|---|---|
| `kokoro_tts_flutter` 0.2.0+1 (MIT) | Kokoro on `flutter_onnxruntime`, phonemizing with `malsami` | Not stated | Docs are inconsistent (version, voices file name); recommends converting voices to JSON; says nothing about unknown words. Worth reading and prototyping against, not a dependency to trust blind |
| `flutter_kokoro_tts` 0.0.1 | Android and iOS only; uses espeak-ng; downloads the model on first use | No | Useful as a reference for how espeak-ng data is packaged |
| `neural_tts` 0.4.x | Android only (desktop is a roadmap item); espeak-ng; multiple engines | No | |

All three are small projects (hundreds of downloads). Evaluate by reading their source and plan to own the engine.

#### 6.5b.11 Compatibility notes

- **Glossary values may be phoneme markup.** `applyPronunciations` replaces a word with its value as plain text, so a glossary row like `Urza,[Urza](/ˈɜɹzə/)` flows through unchanged into either engine, and into the Python CLI's server (English only, per Kokoro-FastAPI's README). The Words step and `unresolvedWords` should treat such entries as resolved.
- **`voice_settings.json`:** for the embedded engine also record `engine` and `model`. The Python CLI only compares the keys it knows, so extra keys are harmless; treat a missing `engine` as the HTTP engine. Switching engine or precision mid-book triggers the same "finished chapters keep the old voice" warning.
- **Don't mix engines inside one book.** G2P details, chunk seams and normalization differ, so finished chapters from one engine will sound slightly different from the other's.

### 6.6 Audio pipeline: chunks → chapter → `.m4b` (ffmpeg)

Three ffmpeg steps; commands are in Appendix B.

1. **Chunks → one chapter FLAC.** Write a concat list (`file '<abs path>'` per chunk, `'` escaped as `'\''`), then ffmpeg concat + (if `fx`) the deep-voice filter, output FLAC. Sample rate is probed from the first chunk with `ffprobe`.
2. **The deep-voice filter.** `asetrate=<sr×pitch>,aresample=<sr>,atempo=<tempo/pitch>,bass=g=<dB>:f=150`. `asetrate` drops pitch **and** speed by the pitch factor; `atempo = tempo/pitch` then corrects so the final speed equals `tempo`. Keep server `speed` at 1.0; heavy server-side slowing caused mispronunciations before (`AGENTS.md`).
3. **Chapters → `.m4b`.** Concat all chapter FLACs, attach an FFMETADATA file with one `[CHAPTER]` per chapter (millisecond timebase, durations from `ffprobe`), encode AAC 96 kbps with `+faststart`, and use `-f ipod` for `.m4b`. Chapter titles go through `ff_escape` (backslash-escape `= ; # \` and newlines).

```dart
String buildFilter(int sampleRate, double pitch, double tempo, num bassDb) =>
    'asetrate=${(sampleRate * pitch).toInt()},aresample=$sampleRate,'
    'atempo=${(tempo / pitch).toStringAsFixed(5)},bass=g=$bassDb:f=150';

String concatLine(String path) =>
    "file '${File(path).absolute.path.replaceAll("'", r"'\''")}'\n";

String ffEscape(String s) => s.replaceAllMapped(RegExp(r'[=;#\\\n]'), (m) => '\\${m[0]}');
```

**`FfmpegService`** wraps `Process.run('ffmpeg', args)` with an **argument list**, so there is no shell quoting to get wrong. Titles with spaces and apostrophes ("The Brothers' War") are safe as arguments; only the concat list files and metadata need escaping. On non-zero exit, log full stderr and throw. Expose `probeSampleRate`, `probeDuration`, `probeChapterCount`.

**Finding ffmpeg.** GUI apps do not inherit the shell `PATH` (on macOS, Homebrew's `/opt/homebrew/bin` is typically absent). Offer a Settings field for the binary path, auto-detect common locations, and show a clear "ffmpeg not found" state. Bundling a binary is a later decision (§8, §12).

### 6.7 The job runner: resumable conversion (`main()`)

This is the heart of the app. Port it as a class that emits events; the UI subscribes.

**Algorithm**

```
sections = extract(epub); if empty -> error "No readable sections found."
workDir.create(); open log; check voice_settings.json (below)
todoChars = sum(chars of sections whose chapter_XX.flac doesn't exist)
for each section i:
    if chapter_XX.flac exists -> emit Skipped; continue
    spoken = applyPronunciations(text) -> expandRomanNumerals (unless disabled) -> chunk
    for each chunk j:
        if chapter_XX_part_YYY.flac exists and size > 0 -> reuse
        else synthesize -> write
    concat chunks -> chapter_XX.flac (with fx if enabled); delete chunk files
    emit ChapterDone(audioSeconds, elapsed, eta)   // eta = elapsed / doneChars * (todoChars - doneChars)
log pronunciation hit counts and Roman-numeral hits
combine chapters -> <slug>.m4b ; log size, total audio, chapter-marker count
```

**Voice-settings guard (`check_voice_settings`).** On first run write `voice_settings.json` (`voice, speed, pitch, tempo, bass_db, fx`; with the embedded engine also `engine` and `model`, see §6.5b.11). On later runs, if any value differs, warn and explain: finished chapters keep the old voice; delete their `chapter_XX.flac` files to redo them, or delete `voice_settings.json` to accept the new settings. In the app, turn the warning into a dialog with those two actions. Compare numbers as `num` (JSON may give `1` where you stored `1.0`).

**Events (sealed class)**

```dart
sealed class PipelineEvent { const PipelineEvent(); }
class SectionsFound extends PipelineEvent { const SectionsFound(this.sections); final List<Section> sections; }
class SettingsMismatch extends PipelineEvent { const SettingsMismatch(this.diff); final Map<String, (Object?, Object?)> diff; }
class ChapterSkipped extends PipelineEvent { const ChapterSkipped(this.index, this.title); final int index; final String title; }
class ChunkStarted extends PipelineEvent { const ChunkStarted(this.chapter, this.chunk, this.chunks); final int chapter, chunk, chunks; }
class ChunkDone extends PipelineEvent { const ChunkDone(this.chapter, this.chunk, this.chars, this.took); final int chapter, chunk, chars; final Duration took; }
class ChapterDone extends PipelineEvent { const ChapterDone(this.index, this.title, this.audio, this.elapsed, this.eta); final int index; final String title; final Duration audio, elapsed, eta; }
class Combining extends PipelineEvent { const Combining(); }
class Finished extends PipelineEvent { const Finished(this.path, this.bytes, this.totalAudio, this.chapterMarkers); final String path; final int bytes, chapterMarkers; final Duration totalAudio; }
class Failed extends PipelineEvent { const Failed(this.message, {this.hint}); final String message; final String? hint; }
```

**Logging.** Keep appending to `convert.log` in the same shape (`YYYY-MM-DD HH:MM:SS message`) so a user can open the file in either tool. Also stream the same lines to a collapsible log panel in the UI.

**Cancel and resume.** Cancel between chunks and kill the running ffmpeg process. Because chapters and chunks are files on disk, "resume" needs no extra state: rerun and the runner skips what exists. Show a "Redo chapter" action that deletes `chapter_XX.flac` (new pronunciations only affect chapters generated afterwards, as the README says).

**Concurrency.** The Python is strictly sequential, and the Kokoro server is the bottleneck. Keep it sequential in v1. Parallel chunk requests are a possible later optimization; verify it helps on your server before adding the complexity.

### 6.8 Voice profiles (`voice_profiles.py`)

**Schema** (`voices/<name>.json`, every key optional): `description` (text), `voice` (non-empty text), `speed`, `pitch`, `tempo`, `bass_db` (positive numbers, not booleans), `fx` (boolean). Unknown keys are an error. The file name without `.json` is the profile name; `new NAME` only allows letters, digits, `-`, `_`.

**Resolution order:** explicit override (a flag in the CLI, a field in the UI) → profile → built-in default. The `fx` flag has one extra rule set:

```
noFx            -> false
fxFlag          -> true
profile has fx  -> that value
profile given   -> true
otherwise       -> fxDefault   (true for conversion; false for the single-word test unless a profile or --fx)
```

```dart
VoiceSettings resolveVoice({
  VoiceProfile? profile,
  VoiceOverrides overrides = const VoiceOverrides(),
  bool fxDefault = true,
}) { /* port of resolve_voice */ }
```

**UI.** A Voices screen listing profiles with sliders for pitch/tempo/bass, a text field for the voice or blend (with a "my server rejects blends" shortcut that switches to plain `am_onyx`), and a **Preview** button that renders a test sentence through the real pipeline (Kokoro + the same ffmpeg filter) so what you hear is what the book will sound like. Ship the two existing profiles as seed data.

**Embedded engine.** With the local engine the voice list comes from the downloaded voice files rather than a server call, and blends are resolved by the app (§6.5b.6), so the "server rejects blends" shortcut only matters for the HTTP engine. Keep `speed` at 1.0 as before.

### 6.9 Pronunciation Lab (replaces `test_pronunciation.py`, `test_glossary.py`, `review_pronunciations.py`, `play_audio.py`)

**What the CLI tools do**

- *Single word test:* render `"The name {word} echoed through the hall."` twice (as written, and respelled), optionally with the deep-voice filter.
- *Glossary test:* render as-written and respelled clips for **every non-blank entry**, name clips `slug(word)_label_slug(said).flac`, reuse clips that already exist (including in `clips/reviewed/`), join them with pauses (0.6 s within a word, 1.4 s between words) into one review file plus a timestamped index, and write `manifest.json`.
- *Review:* play clip 1 (Kokoro's own) then clip 2 (respelling) and ask `1`, `2`, `r` (repeat) or `q` (save and quit). Decisions are saved after every word in `review_results.json`, keyed to the specific respelling (so changing a respelling re-opens the question). Picking clip 1 writes a **blank** respelling ("keep Kokoro's pronunciation"); picking clip 2 keeps the respelling. The glossary is only written when every word is decided, or on `--apply`. Decided clips move to `clips/reviewed/` and are ignored afterwards unless `--redo`.
- *Playback:* first available of ffplay, mpv, VLC, afplay, pw-play, paplay, sox, aplay, Windows SoundPlayer; converts to WAV when a player can't read FLAC.

**In the app**

- You don't need the concatenated review file or timestamp index. Play clips directly with an audio package (D6) and drop `play_audio.py` entirely.
- A **Review mode** card: the word, two big buttons (A / B), Repeat, Skip, progress bar, keyboard shortcuts (1, 2, R, Q). Options mirroring the flags: *blind* (randomize which clip is A, `--shuffle`), *shuffle word order*, *show respelling*, *redo decided*, *apply decisions so far*, *dry run* (show the diff only).
- A **Quick test** field: type a word and a respelling, hear both immediately. Also lets the user edit the test sentence (`{word}` placeholder).
- Keep `manifest.json` / `review_results.json` / `clips/` formats if you want CLI interop; otherwise a single JSON per glossary is fine. Say which in your decision log.
- Render clips through `ClipRenderer` (the active `TtsEngine`, then the optional fx filter). Do the work in a queue with progress; entries are independent.
- **Embedded-engine extras.** Show the phonemes the engine produced for each word, flag words that came back unresolved, let the user edit the phonemes directly (stored as `[word](/phonemes/)` markup, §6.3), and, if espeak-ng is configured, offer "suggest phonemes from this respelling" (§6.5b.3).

### 6.10 Glossary manager (`update_glossary.py`)

**Merge rules** (also Appendix D). `merge(source, glossary)` copies only **filled-in** source entries:

- word not in glossary → added;
- same value → nothing;
- different value → **conflict**: glossary keeps its own unless `overwrite`, in which case source replaces it; every clash is reported;
- a **blank row already in the glossary** counts as an existing decision ("keep Kokoro's") and is kept, even against a filled-in source entry, unless `overwrite`.

```dart
class MergeResult {
  final List<String> added;
  final List<String> replaced;    // "word: 'old' -> 'new'"
  final List<String> conflicts;   // "word: keeping 'x', book has 'y'"
  final PronunciationTable result;
}
MergeResult mergeGlossary(PronunciationTable source, PronunciationTable glossary, {bool overwrite = false});
```

**Known limitation to fix.** The README documents that blank decisions in a staging glossary are **not** copied into the main glossary (only filled-in entries are). In the app you can carry those across, since the Lab already knows the difference between "never reviewed" and "reviewed, Kokoro's is fine". If you do, record it in the changelog as a deliberate behavior change.

**UI.** A searchable table editor (filter: all / filled / blank / conflicts), import from a book's `words.csv` or another glossary with a **diff preview** (added / replaced / conflicts, then Apply), and an ordered "stack" for conversion: drag to reorder, later wins, the book's own `words.csv` always last. Matches the README's "main glossary first, staging after it" workflow.

### 6.11 The wizard (replaces `make-audiobook.sh`)

The script has two phases, selected by whether `output/<slug>/words.csv` exists. In the app that becomes explicit steps:

| Step | Replaces | Notes |
|---|---|---|
| 1. Import | `cp book.epub books/`, slug choice | Pick epub, propose a slug, copy into `books/`. Sanitize the slug/work folder: `[^\w.-]+` → `_`. |
| 2. Sections | `--list` | Show the section list with char counts and the reason each was kept or skipped. Let the user include/exclude sections (an improvement over editing regex constants). |
| 3. Words | phase 1 (`find_unknown_words.py`) | Generate `words.csv` if absent; table editor; glossary stack. **Regenerate** (`--refresh`) must confirm, because it overwrites the user's work. |
| 4. Voice | `--profile`, `--voice`, `--tempo`… | Profile picker, overrides, Roman-numeral toggle, quick preview. |
| 5. Convert | phase 2 | Progress per chapter and chunk, ETA, log panel, cancel. Blocks with a clear message if the engine isn't ready (model not downloaded, or server unreachable), ffmpeg is missing, or the embedded engine reports unresolved words (§6.5b.3). |
| 6. Done | `.m4b`, `update_glossary.py` | Open folder, play, offer "Save these pronunciations to a series glossary" (opens the merge preview). |

Also port: the `names.csv` → `words.csv` auto-rename for books started before the rename.

### 6.12 Settings

Engine (Local / Server), a model manager for the local engine (download, verify, delete, precision, "use my own files"), the optional espeak-ng path, server URL (with Test connection) for the HTTP engine, ffmpeg/ffprobe path, workspace folder, default profile, default glossary stack per series, Roman-numeral default. Store as a small JSON file or `shared_preferences`. The server URL is a user setting only; never commit or log it.

### 6.13 Optional: finished-book player

`play_audio.py --start 1:30:00` exists so you can spot-check long outputs. In-app: list chapters (`ffprobe -show_chapters`), click to seek and play. Nice to have, not v1.

### 6.14 What does *not* get ported

- `tools/skill/SKILL.md` (the Claude skill that researches pronunciations and drives the CLI). Keep it while the Python tools live in the repo. Possible later feature: an in-app "Suggest pronunciations" action. `AGENTS.md`'s rule still applies to any such feature: never invent a pronunciation, mark uncertain ones, and let the user decide.
- The `.py` pronunciation format (D8), the paste-ready template printed by `find_unknown_words.py`, and the `--out` format switching (the app has a UI and writes CSV).

---

## 7. UI: screens and flow

```
┌ Library ─────────────────────────────────────────────────────────────┐
│ [+ Add book]                                          [Settings ⚙]   │
│ ┌──────────────┐ ┌──────────────┐                                    │
│ │ The Brothers'│ │ Arthas       │   status chip: Words / Ready /     │
│ │ War          │ │ 12/31 ch.    │   Converting / Done                │
│ └──────────────┘ └──────────────┘                                    │
└──────────────────────────────────────────────────────────────────────┘

Book wizard:   ① Sections  ② Words  ③ Voice  ④ Convert  ⑤ Done        (stepper along the top)

Convert step:  [██████████░░░░░░░░░] 12/31   ETA 2h 14m
               Chapter 13: "Part Two: The Golden Boy" - chunk 4/9
               ▸ Log (collapsible, same lines as convert.log)       [Cancel]
```

Other top-level destinations: **Glossaries**, **Voices**, **Pronunciation Lab**, **Settings**.

State that must survive restarts: the library is just a scan of `output/*/` plus `books/`; wizard progress is derived from files on disk (`words.csv` exists? chapter files exist?). That's what makes the app and the CLI interchangeable (D2).

---

## 8. Platform notes

- **macOS.** Two gotchas. (1) Flutter's macOS entitlements: add `com.apple.security.network.client` to **both** `DebugProfile.entitlements` and `Release.entitlements` or HTTP requests to Kokoro fail in release builds. (2) The **App Sandbox** blocks launching arbitrary binaries and restricts file access. Either disable the sandbox (fine for direct distribution, not for the Mac App Store) or bundle ffmpeg inside the app and use security-scoped folder access. GUI apps also don't see Homebrew's `PATH`; use the explicit ffmpeg path setting.
- **Windows.** Look for `ffmpeg.exe` via a Settings path and `where`. `Process` with an argument list handles spaces and apostrophes. Watch long paths for deep chapter folders.
- **Linux.** Snap/Flatpak sandboxes can hide the host `ffmpeg`; document it, or bundle one. Audio playback packages need their system libraries; check them on your target distros.
- **ONNX Runtime (embedded engine).** Per its pub.dev page, `flutter_onnxruntime` ships no prebuilt native libraries: it downloads the official ONNX Runtime at build time on Linux and Windows and uses CocoaPods or Swift Package Manager on macOS (minimum macOS 14 per the page). The first build therefore needs network access, and CI must allow it or vendor the libraries. fp16 models aren't fully supported on Linux and Windows yet, hence fp32 as the default (D13).
- **Model storage.** Models are roughly 90 to 330 MB. Keep them in the per-user app data folder, not the workspace, keep them out of git, and check free disk space before downloading.
- **espeak-ng (bundled).** Ship the executable and its `espeak-ng-data` directory inside the app bundle and resolve them relative to the app, not through `PATH` (on macOS, GUI apps don't get your shell `PATH`). On macOS the bundled binary also has to be code-signed and notarized with the app. Keep a Settings override for a custom path. Details in §6.5b.3.
- **Sustained CPU load.** Hours of inference will keep the machine busy; show the time estimate up front and rely on chunk-level cancel/resume.
- **Bundling ffmpeg** (optional, later). Check the license of the specific build you ship (LGPL vs GPL builds differ in obligations). The pipeline only needs the built-in `aac` encoder, FLAC, and the filters above.
- **Packaging.** MSIX or installer for Windows, signed/notarized DMG for macOS, AppImage/deb/Flatpak for Linux.

### 8.1 License and notices (GPL-3.0-or-later)

- **Repo:** add the full GPLv3 text as `LICENSE`, put `SPDX-License-Identifier: GPL-3.0-or-later` in each source file, and add a `CONTRIBUTING` note that contributions come in under the same license.
- **`THIRD_PARTY_NOTICES`:** one entry per bundled component with its license and source link. Known so far: espeak-ng (GPL-3.0-or-later; its repo also carries other license files for parts of its tree, so carry those notices too), ONNX Runtime and `flutter_onnxruntime` (MIT), Kokoro-82M (Apache-2.0, with upstream credits), misaki data if you port it (Apache-2.0), the English dictionaries and the word list from pyspellchecker (check their licenses before bundling), ffmpeg (LGPL or GPL depending on how the build was configured), Flutter/Dart and your pub packages (check each).
- **In the app:** Flutter's `showLicensePage` lists registered package licenses; add natively bundled components yourself with `LicenseRegistry.addLicense`. Put the same credits in the About screen.
- **Source for binaries:** every release should link the exact tag it was built from, and bundled third-party binaries you built (espeak-ng, ffmpeg) need their corresponding source or a clear link to it.
- **Where to distribute:** GitHub Releases, Homebrew, winget, Flathub or AppImage fit well. GPL is widely considered a poor match for Apple's App Store terms, so don't plan on it.

---

## 9. Python → Dart behavior differences to test for

| Area | Python | Dart | Action |
|---|---|---|---|
| Regex word boundary | `\b`, `\w` are Unicode-aware on `str` (I checked: `\bé\b` matches) | `\b`, `\w` are ASCII-only under ECMAScript rules (I confirmed the same pattern fails in JS even with the `u` flag; Dart wasn't available here, so confirm with a one-line Dart test) | Use the `\p{L}\p{N}_` lookaround version (§6.2); add tests with accented names. Entries that start or end with punctuation behave differently under `\b` than under lookarounds; test them. |
| String length | `len` = code points | `length` = UTF-16 units | Use `runes.length` where parity matters (chunking). |
| `str.title()` | Capitalizes after apostrophes (`"DON'T".title()` → `"Don'T"`) | None | Write a clean title-caser; accept the rare diff. |
| `re.split(..., maxsplit=1)` | Built in | Not available | `firstMatch` + `substring`. |
| Tuple sort with `reverse=True` | Ties come out reverse-alphabetical | You choose | Only matters for byte-exact diffs of `words.csv`. |
| `get_text(" ", strip=True)` | Joins and strips text nodes | `element.text` doesn't | Normalize whitespace; compare against golden files. |
| CSV | Read with `utf-8-sig` (BOM tolerated); written with `\n` | Handle yourself | Strip a leading BOM; force `\n` line endings. |
| ebooklib TOC | `ignore_ncx=True` → TOC from the EPUB 3 nav doc | Your reader decides | Test on your real library; consider an NCX fallback. |
| JSON numbers | `1 == 1.0` | `1 == 1.0` is also true for `num`, but a decoded `int` vs `double` can trip strict comparisons | Compare settings as `num`. |
| Subprocess quoting | List args, no shell | `Process.run(exe, args)` — same | Keep list args; only the concat list and metadata need escaping. |
| `ast.literal_eval` | `.py` pronunciation files | No equivalent | Drop `.py` (D8). |
| Text normalization | Done by Kokoro-FastAPI before G2P | Nothing unless you write it | Build `TextNormalizer` (§6.5b.4); compare against the server. |
| G2P | misaki (Python): dictionaries, rules, espeak-ng fallback | Port or package (§6.5b.3) | Phoneme goldens; track the unresolved-word rate. |
| Token limit | The server re-splits by tokens (model max 510) | You enforce at most 510 real tokens per utterance | Contract tests (§10.5). |
| Partial chunk files | Python writes a chunk only after a complete response | Piping PCM to ffmpeg can leave a truncated file if the process is killed | Write `*.part`, rename when ffmpeg exits cleanly; resume only reuses finished files. |

---

## 10. Testing and parity strategy

### 10.1 Golden-file parity (do this first)

Add this tiny script next to the Python tools. It dumps what the Python pipeline produces for a given epub and glossary stack; I ran it against a small test epub and it works:

```python
#!/usr/bin/env python3
"""Dump what the Python pipeline produces for an epub, so a Dart port can be diffed against it.

usage (run from the repo's tools/ folder):
  python dump_golden.py ../books/Some.epub [../glossaries/series.csv ...] > golden/some.json
"""
import json
import sys

from epub_to_kokoro import apply_pronunciations, chunk_text, expand_roman_numerals, extract_sections, load_pronunciations

epub, *pron_files = sys.argv[1:]
pron = {}
for f in pron_files:
    pron.update(load_pronunciations(f))

out = []
for i, (title, text) in enumerate(extract_sections(epub), 1):
    spoken = expand_roman_numerals(apply_pronunciations(text, pron))
    out.append({"index": i, "title": title, "chars": len(text), "chunks": chunk_text(spoken)})
json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
print()
```

Generate goldens for 3 to 5 real epubs with varied structure (image-titled chapters, `Book I`/`Part 2` headings, a series glossary, Roman numerals, a book with accented names). The Dart test loads the same epub and asserts equal section titles, char counts and chunk lists. Do the same for `words.csv` (same words and counts) once §6.4 is ported, treating tie order and the accented-name decision as known, documented differences.

### 10.2 Unit tests (`bardoro_core`)

- Section filtering: include/skip regexes, 3000-char threshold, title rules (heading, `Book I: Subtitle`, image alt, TOC fallback, numbering continuation, spoken title).
- `applyPronunciations`: whole-word, case-sensitive, longest-first (`Urza Planeswalker` beats `Urza`), Unicode boundaries, hit counts.
- Roman numerals: `Part II` → `Part two`, `Menethil II` → `Menethil the Second`, lone `I`/`V`/`X` untouched, glossary override wins.
- Pronunciation file loaders: each format, BOM, blank handling, `keepBlank`.
- Voice resolution: precedence and every `fx` branch; profile validation errors.
- Glossary merge: every row of Appendix D.
- Filter builder and `concatLine`/`ffEscape` with apostrophes, `=`, `;`, `#`, backslashes.

### 10.3 Integration test: port of `tests/smoke_test.sh`

The smoke test builds a tiny epub (with an apostrophe in the title on purpose), runs both phases against a fake Kokoro server, and checks: names found; respellings from both a glossary and the book file reach the server; the unreplaced name never does; three chapters and three chapter markers in the `.m4b`; a rerun makes **zero** new server calls; the glossary update works. Recreate this in Dart:

- A fake server with `shelf` (or `dart:io` `HttpServer`) that records each request body and returns a short FLAC tone. The Python fake generates the tone with `ffmpeg -f lavfi -i sine=frequency=220:duration=…`, length depending on text size. Do the same, or check in a small fixture FLAC.
- Build the epub in test code (the `archive` package can write a zip) or check in a fixture.
- Assert with `ffprobe` that the output has the expected chapter count.
- CI needs ffmpeg installed. Keep the existing `tests/smoke_test.sh` running too, until the Python tools are retired.

### 10.4 Widget tests

Wizard step gating (can't convert without words reviewed, engine ready, ffmpeg found), progress rendering from a scripted `PipelineEvent` stream, review-mode state machine (decision stored per respelling; changing a respelling re-opens a word).

### 10.5 Embedded engine tests

- **Engine contract tests**, run against both engines: a chunk yields a non-empty FLAC; resume never reuses a truncated file (write `*.part`, then rename); a cancelled synthesis leaves nothing behind that looks finished.
- **Tokenizer:** known phoneme strings map to the expected ids (take goldens from the Python reference), missing characters are reported, padding adds exactly one `0` at each end.
- **Utterance chunker:** never more than 510 real tokens, sentence order preserved, over-long sentences split.
- **VoiceBank:** `a(4)+b(1)` equals `0.8·a + 0.2·b` element by element; a single voice is returned unchanged; an unknown voice is an error; a missing weight means 1.
- **Phonemizer goldens:** write a sibling of `dump_golden.py` that prints misaki's phonemes for a corpus of sentences (see misaki's README for the G2P call) and compare. Compare against the HTTP server's `/dev/phonemize` too. Track the **unresolved-word rate per book** as a metric.
- **Overrides:** `[word](/ipa/)` markup yields exactly those phonemes; a hyphenated respelling is reported as unresolved when no fallback is configured.
- **Inference smoke test:** with the real model and a fixed token sequence, assert the audio duration falls in a plausible range and isn't silent. Skip it in CI when the model isn't cached. Don't assert exact samples; they differ across runtimes and precisions.

---

## 11. Phased plan with exit criteria

| Phase | Work | Done when |
|---|---|---|
| **0. Scaffold** | Monorepo, `bardoro_core` + `bardoro_app`, lints, CI that runs `dart test` and `flutter test`; seed assets (profiles, the two glossaries); `Workspace` path helpers matching §4.2; `LICENSE` (GPL-3.0-or-later), SPDX headers and a third-party notices file (§8.1). | CI green on an empty skeleton; workspace layout documented. |
| **0b. Spikes (de-risk the embedded engine)** | **S1** run the Kokoro ONNX model through `flutter_onnxruntime` on Windows, macOS and Linux, using token ids produced by the Python reference, and listen to the result. **S2** measure real-time factor: fp32 vs int8, CPU vs any available execution provider. **S3** pick the G2P approach and measure the unresolved-word rate on 3 real books, comparing phonemes with the HTTP server's `/dev/phonemize`. **S4** A/B a chapter excerpt, embedded vs server (seams, pace, loudness, numbers). **S5** bundle espeak-ng on all three OSes (subprocess vs FFI), port the IPA → Kokoro phoneme mapping, and measure the unresolved-word rate and the speed cost with and without it (§6.5b.3). | A written go/no-go with numbers: audio plays on all three OSes, a full-book time estimate you can live with, and a known unresolved-word rate. |
| **1. Text core** | `EpubReader`, `SectionExtractor`, stray cleaner, pronunciation loader/applier, Roman numerals, chunker, unknown-word finder + dictionary asset, `dump_golden.py`. | Golden parity suite passes on the chosen sample books; documented list of intentional diffs. |
| **2. Audio core** | `VoiceSettings`/profiles/resolver, `TtsEngine` + `KokoroHttpEngine`, `FfmpegService`, `PipelineRunner` with events, voice-settings guard, logging, headless `bin/bardoro.dart`. | The Dart integration test (§10.3) passes, and a real book converts end to end via the headless CLI, resumes after a kill, and produces correct chapter markers. |
| **2b. Embedded engine** | `LocalOnnxEngine`: text normalizer, phonemizer (all four tiers, with bundled espeak-ng, an IPA → Kokoro mapping and a per-word phoneme cache), tokenizer, utterance chunker, `VoiceBank` with blending, `KokoroSession`, PCM→FLAC, `ModelManager`, `unresolvedWords` reporting. | The engine passes the shared contract tests (§10.5), converts a real chapter with no server running, resumes correctly, and the `deep-narrator` blend sounds right next to the server's output. |
| **3. App shell + wizard** | Settings (engine, model download, URL, ffmpeg, workspace), Library, wizard steps 1–6, progress UI, cancel/resume, log panel. | An epub goes to `.m4b` entirely from the GUI; the CLI can resume a GUI-started book and vice versa. |
| **4. Glossaries + Words** | Table editors, glossary stack, merge preview, "save to series glossary" at the end of a book. | All Appendix D rules covered by tests and visible in the diff preview. |
| **5. Pronunciation Lab** | Quick test, batch render, review mode, apply/dry-run, playback. | A glossary can be reviewed by ear end to end and written back; decisions survive a restart. |
| **6. Hardening and release** | Packaging per OS, ffmpeg detection/bundling decision, license compliance (notices screen, source links for bundled binaries, §8.1), error states, large-book performance (isolates), accessibility pass, docs. | Installable builds on all three OSes; a 500+ page book converts without UI stalls. |

Retire `tools/` Python only after Phase 3 parity, and keep `tools/skill/SKILL.md` for as long as the Python CLI is the thing the skill drives.

---

## 12. Open questions for you

1. **Repo shape.** Same repo with Python and Dart side by side during migration (recommended), or a new repo?
2. **Accented names.** Improve the tokenizer with Unicode letters in the unknown-word finder (better results, breaks byte-parity), or ship parity first and improve later?
3. **ffmpeg.** Require a user-installed ffmpeg (simplest), or bundle one per platform (nicer UX; the GPL project makes licensing easier, but per-OS builds, size and signing remain)?
4. **Mac distribution.** Direct download (sandbox off, simplest) or Mac App Store (sandbox on, bundle ffmpeg)?
5. **Section picking.** Keep the regex-constant approach only, or add per-section include/exclude toggles in the UI?
6. **Parallelism.** Is the Kokoro server fast enough that parallel chunk requests would help, or is it GPU-bound?
7. **Interop window.** How long do you want the CLI and the app to share one workspace? That sets how strict D2 has to stay.
8. **Pronunciation suggestions.** A later in-app "suggest respellings" feature (the skill does this today via research), or leave that to Claude?
9. **Distribution channels.** Decided: open and free under GPL-3.0-or-later (D14). Which channels will you use (GitHub Releases, Homebrew, winget, Flathub/AppImage)? The Mac App Store is a poor fit for GPL.
10. **espeak-ng packaging.** Decided: bundled. Still open: subprocess or FFI, and how you'll build and ship it per OS (spike S5).
11. **Default precision.** fp32 (326 MB, best fidelity) or int8 (114 MB, faster, measurably lower spectral correlation per kokoro-onnx's notes)? Decide after S2 and an A/B listen.
12. **Acceleration.** Is CPU inference fast enough for a multi-hour book, or do you need GPU/NPU execution providers? That depends on S2 and on which providers `flutter_onnxruntime` really exposes on your OSes.
13. **Model hosting.** Download from Hugging Face on first run (pinning file URLs and hashes), or let users supply files? Verify the exact URLs; I couldn't.

---

## Appendix A: Kokoro HTTP contract (as used by the optional HTTP engine)

```
POST {KOKORO_URL}/v1/audio/speech
{ "model": "kokoro", "input": "<text>", "voice": "am_onyx(4)+am_adam(1)",
  "response_format": "flac", "speed": 1.0 }
-> 200, body = FLAC bytes (sample rate probed from the first chunk; Kokoro commonly outputs 24 kHz)
-> non-200 or empty body -> failure (retry up to 3x, 3s*attempt backoff, 900s timeout)
-> error text containing "voice" and ("not found" | "invalid") -> abort, suggest plain voice
```

## Appendix B: ffmpeg and ffprobe commands

Chunks → chapter (with effect; example for a 24 kHz source, pitch 0.94, tempo 0.90, bass 4 dB):

```
ffmpeg -y -v error -f concat -safe 0 -i chapter_01_list.txt \
  -af "asetrate=22560,aresample=24000,atempo=0.95745,bass=g=4:f=150" \
  -c:a flac chapter_01.flac
```

Without the effect, omit `-af`.

Chapters → `.m4b`:

```
ffmpeg -y -v error -f concat -safe 0 -i all_chapters.txt -i chapters_meta.txt \
  -map 0:a -map_metadata 1 -map_chapters 1 \
  -c:a aac -b:a 96k -movflags +faststart -f ipod "<slug>.m4b"
```

(`-f ipod` only for `.m4b`; `.mp3`/`.m4a` outputs skip it.)

`chapters_meta.txt`:

```
;FFMETADATA1
title=<output file stem, escaped>
[CHAPTER]
TIMEBASE=1/1000
START=0
END=<duration of chapter 1 in ms>
title=<chapter title, escaped>
[CHAPTER]
TIMEBASE=1/1000
START=<previous END>
...
```

Probes:

```
ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=nw=1:nk=1 <file>
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 <file>
ffprobe -v error -show_entries chapter=id -of default=nw=1:nk=1 <m4b>     # one line per chapter
```

## Appendix C: File formats

`output/<slug>/words.csv` (per book; written by the word finder, edited by the user):

```csv
word,count,pronunciation
Urza,412,Er-zuh
Tocasia,96,
```

`glossaries/<series>.csv`:

```csv
word,pronunciation
Antonidas,An-tahn-ih-dus
Aedelas,
```

A blank second column means "reviewed, keep Kokoro's pronunciation" in a glossary, and "not respelled" in `words.csv`.

```json
// voices/<name>.json  (every key optional)
{
  "description": "The default deep male narrator",
  "voice": "am_onyx(4)+am_adam(1)",
  "speed": 1.0, "pitch": 0.94, "tempo": 0.90, "bass_db": 4, "fx": true
}
```

`chapters/voice_settings.json` holds `voice, speed, pitch, tempo, bass_db, fx` for the book.

## Appendix D: Glossary rules (the behavior to encode in tests)

| Situation | Rule |
|---|---|
| Converting with several glossaries | Later files override earlier ones; the book's `words.csv` is applied last of all. |
| A blank pronunciation in a later file | Never cancels an earlier respelling. Blank = "nothing to apply". |
| `merge(source, glossary)` | Copies only filled-in source entries. Words missing from the glossary are added. A differing value is a **conflict**: the glossary keeps its own, and the conflict is reported. `overwrite` makes the source win. |
| Merging several sources in turn | Without `overwrite`, the first merged wins a clash. Run each with a dry run and read the conflicts. |
| A blank row already in the glossary | Counts as an existing decision and is kept, even against a filled-in source entry, unless `overwrite`. |
| Matching | Whole word, case-sensitive, longest entry first. |

## Appendix E: CLI flag → app setting

| CLI flag | App equivalent |
|---|---|
| `--url`, `$KOKORO_URL` | Settings → Engine (Local / Server), and Server URL for the HTTP engine |
| `--glossary FILE` (repeatable) | Wizard → Words → glossary stack (ordered) |
| `--list` | Wizard → Sections step |
| `--refresh` | Words step → "Regenerate" (confirm: overwrites `words.csv`) |
| `--profile NAME`, `--list-profiles` | Voice step profile picker; Voices screen |
| `--voice`, `--speed`, `--pitch`, `--tempo`, `--bass`, `--no-fx` | Voice step overrides |
| `--no-roman-numerals` | Voice step toggle |
| `--pronunciations FILE...` | Glossary stack + the book's `words.csv` |
| `--out`, `--work`, `--log` | Fixed by the workspace layout (§4.2) |
| `--min-count`, `--top`, `--known` | Words step: min count filter, ignore list |
| `test_pronunciation.py --sentence/--fx/--max` | Lab → Quick test (sentence field, effect toggle) |
| `test_glossary.py --words/--start/--max/--respelled-only` | Lab → Batch render options |
| `review_pronunciations.py --shuffle/--redo/--apply/--dry-run` | Lab → Review mode options |
| `update_glossary.py --dry-run/--overwrite` | Glossary merge preview with an Overwrite toggle |
| `play_audio.py --start` | In-app player seek |
| (new) engine choice, model precision, espeak-ng path | Settings → Engine / Model manager (§6.12) |

## Appendix F: Embedded inference reference (external sources)

Everything here was read from the linked pages. None of it was run, and the package pages were snapshots at the time of reading.

| Topic | What the sources say |
|---|---|
| Model | Kokoro-82M v1.0 as ONNX: 82M parameters, Apache-2.0, finetuned from `hexgrad/Kokoro-82M` |
| Files (onnx-community) | fp32 326 MB · fp16 163 MB · quantized 92.4 MB · q8f16 86 MB · uint8 177 MB · uint8f16 114 MB · q4 305 MB · q4f16 154 MB |
| Files (kokoro-onnx releases) | `kokoro-v1.0.onnx` 326 MB · fp16 164 MB (spectral correlation vs fp32 0.999) · int8 114 MB (0.916) · `voices-v1.0.bin` 28 MB, 54 voices, npz |
| Inputs | `tokens` (card says `input_ids`) int64 `(1, N)`, N ≤ 512, padded with 0 at both ends (≤ 510 real tokens); `style` `(1, 256)` float32; `speed` `(1,)` float32 (verified on kokoro-v1.0.onnx) |
| Output | Waveform at 24,000 Hz |
| Voices | 256-float rows; style = `voices[len(tokens)]` per the card, `[len-1]` per kokoro-onnx, after reshaping to `(-1, 1, 256)`; per-voice raw float32 `.bin` (onnx-community) or an npz bundle (kokoro-onnx) |
| Vocabulary | Phoneme-character → id map in `config.json` of `hexgrad/Kokoro-82M` |
| G2P | misaki (Apache-2.0): English dictionaries + rules; espeak-ng fallback for out-of-dictionary words; `fallback=None` disables it; a non-espeak fallback is a TODO |
| Inline phonemes | `[word](/phonemes/)`, English only; supported by misaki, Kokoro-FastAPI and malsami |
| Kokoro-FastAPI | Blend syntax `a(2)+b(1)`, ratios normalized to 100%; input text normalization (switchable); token targets 175 / 250 / 450 and a 510 model max; `/dev/phonemize` for inspecting phonemes; `/v1/audio/voices/combine` exports a blended voicepack |
| espeak-ng | GPL version 3 or later (the repo page doesn't discuss linking or embedding) |
| `voice-g2p` (Rust, MIT) | English-only port of misaki's pipeline; about 90k gold + 93k silver dictionary entries; espeak-ng optional for unknown words |
| `malsami` 0.0.3 (Dart, MIT) | English dictionary G2P inspired by misaki; inline phoneme markup; no OOV fallback; unverified uploader; about 16 months since publish at the time read |
| `flutter_onnxruntime` 1.9.0 (MIT) | Android, iOS, macOS, Linux, Windows, Web; ONNX Runtime fetched at build/install time (macOS min 14); EP configuration listed on all platforms; fp16 planned, not complete, on Linux/Windows/Web |
| `onnxruntime_v2` 1.23.2+2 | Five of six platforms (no Web), desktop included; published about nine months before the snapshot |
| Kokoro Dart packages | `kokoro_tts_flutter` 0.2.0+1 (MIT; `flutter_onnxruntime` + `malsami`; platforms unstated); `flutter_kokoro_tts` 0.0.1 (Android/iOS, espeak-ng); `neural_tts` 0.4.x (Android only, espeak-ng) |
| Other embedders needing espeak-ng | `kokoroxide` (Rust) and PyKokoro both list espeak-ng as required for phonemization |
| Training-data credits | The Kokoro-82M card notes CC BY audio in the training data (Koniwa, SIWIS) |

**Open facts to confirm in the spikes** (tensor names/dtypes and equal voice row counts are now verified for the v1.0 file): style-row off-by-one; which execution providers work on each OS; real-time factor on your hardware; how `malsami` (or your own port) fares on your books' unknown-word rate.

**Sources**

- [onnx-community/Kokoro-82M-v1.0-ONNX (model card)](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)
- [hexgrad/Kokoro-82M (README)](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/README.md)
- [kokoro-onnx (README)](https://github.com/thewh1teagle/kokoro-onnx) and [its releases](https://github.com/thewh1teagle/kokoro-onnx/releases)
- [misaki (README)](https://github.com/hexgrad/misaki)
- [Kokoro-FastAPI fork README](https://github.com/sheigl/Kokoro-FastAPI) and [docs index](https://docsearch.algolia.com/mcp/docs/repo/remsky/kokoro-fastapi)
- [espeak-ng repository](https://github.com/espeak-ng/espeak-ng)
- [voice-g2p](https://docs.rs/crate/voice-g2p/latest/source/README.md)
- [kokoroxide](https://docs.rs/crate/kokoroxide/0.1.4) and [PyKokoro installation guide](https://pykokoro.readthedocs.io/en/stable/installation.html)
- [flutter_onnxruntime](https://pub.dev/packages/flutter_onnxruntime) and [onnxruntime_v2](https://pub.dev/packages/onnxruntime_v2/score)
- [malsami](https://pub.dev/packages/malsami)
- [kokoro_tts_flutter](https://pub.dev/documentation/kokoro_tts_flutter/latest/), [flutter_kokoro_tts](https://pub.dev/packages/flutter_kokoro_tts), [neural_tts](https://pub.dev/packages/neural_tts)

### Appendix F.1: what kokoro-onnx 0.6.1 does (read from source)

- G2P is espeak-ng only (`phonemizer` + `espeakng-loader`, `preserve_punctuation=True`, `with_stress=True`), then drops any character not in the 114-entry vocab. There is no dictionary, so it is the simplest baseline for spike S3/S5, but numbers and abbreviations get only espeak's own normalization. espeak-ng holds global state: serialize calls with a lock.
- Phoneme string is split at 510 by `split_phonemes`: sentence marks `.!?…`, then clause marks `,;:`, then spaces, then hard slices; batches are balanced so none is much shorter than the rest.
- Each batch is trimmed (a librosa `trim` port) and silence is inserted after sentence (0.25 s) and clause (0.1 s) marks by default.
- `espeakng-loader` 0.2.4 ships the library (about 0.66 MB on Linux) and `espeak-ng-data` (about 19 MB uncompressed), a handy reference for what you must bundle per OS.
