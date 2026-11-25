---
name: bardoro
description: Turn an epub into a chaptered .m4b audiobook through a Kokoro-FastAPI server: find unusual names, research pronunciations from the user's book context, then run the bundled scripts. Use when the user wants an epub made into an audiobook, m4b or text-to-speech narration, or wants names and pronunciations fixed for one. Needs Python 3.9+, the pip packages in scripts/requirements.txt, ffmpeg/ffprobe on PATH and a reachable Kokoro server URL.
---

# Bardoro: epub to Kokoro audiobook

Builds one chaptered `.m4b` from an epub through a Kokoro-FastAPI server, after fixing how invented names and unusual words are pronounced. This directory is the skill; all paths below are relative to it (see `AGENTS.md` for contributor notes).

Skill layout:
- `scripts/make-audiobook.sh EPUB SLUG [--glossary FILE]... [--output-dir DIR] [--list] [--url URL] [-- extra converter args]` is the two-phase wrapper. Phase 1 writes `<outdir>/SLUG_work/words.csv` and stops. Running it again does phase 2 and writes `<outdir>/SLUG.m4b`. `<outdir>` is the current directory unless `--output-dir` is given. `SLUG_work/` holds the working files (`words.csv`, `chapters/`, `convert.log`, `voice_settings.json`) and is kept after the run so fixes can be redone cheaply.
- `scripts/find_unknown_words.py`, `scripts/epub_to_kokoro.py`, `scripts/test_pronunciation.py`, `scripts/update_glossary.py` are the underlying tools.
- `glossaries/<series>.csv` holds shared pronunciations (`word,pronunciation`); `<outdir>/SLUG_work/words.csv` holds one book's (`word,count,pronunciation`).
- `voices/` holds voice profiles (JSON). Glossaries and voice profiles are looked up in two places: the user's current directory (`./glossaries`, `./voices`) first, then this skill's own folders. A local file wins over a shared one of the same name, and `--glossary NAME` / `--profile NAME` accept bare names. `python scripts/resources.py where` shows the folders searched.
- The epub is looked for in the current directory and `./books` (a bare file name works; `python scripts/resources.py epubs` lists what is there).
- `tests/smoke_test.sh` checks the toolchain against a fake server.

## 1. Collect inputs before doing any work

Ask with AskUserQuestion (up to four questions per call; use a second call or plain text for the rest). Do not guess values the user must supply.

**Required**
- Where this skill's directory is, if it is not the working directory (ask once). If the scripts cannot be found, say so; do not rewrite them from memory.
- The epub: first list the `.epub` files in the working directory and `./books` (`python scripts/resources.py epubs`) and offer them as choices; ask for a path only if none are found. Then a short slug for the output folder (for example `brothers-war`).
- Output folder: where the finished `.m4b` and the `<slug>_work/` working folder go. Default to the current directory and offer to change it (pass `--output-dir DIR`). Use that folder for every `<slug>_work/` path below.
- Kokoro server URL (never assume `localhost:8880`; the user may have `KOKORO_URL` set, so confirm it).

**Book context (this is what makes the pronunciations good)**
- Title, author, and series or setting (for example a Magic: The Gathering or Warcraft novel).
- Pronunciations the user already knows, and any official audiobook, wiki or glossary they trust.
- Accent preference for names, if it matters.
- Anything to skip or treat specially.
- Whether a series glossary already exists to reuse: list `./glossaries` and the skill's `glossaries/` (`python scripts/test_glossary.py --list` or `ls`) and offer the match. Mention which one is local and which is shared.

**Settings, offering defaults** (accept "defaults"):
- Voice profile: list them with `python scripts/voice_profiles.py list` (shows local and shared ones; new profiles are saved to `./voices`, or the skill's with `--shared`) and pass `--profile NAME` to the wrapper (a profile is a JSON file in `voices/`; flags override it). Without one, the built-in defaults below apply.
- Voice: default is the server blend `am_onyx(4)+am_adam(1)`; plain `am_onyx` if the server rejects blends.
- Tempo: default `0.90`; `0.88` is noticeably slower. Keep the server speed at 1.0.
- Skip the deep-voice post-processing (`--no-fx`)?

## 2. Check prerequisites

- Run `python3 scripts/check_setup.py` (add `--url <url>` to test the server). It prints `ok` or `MISSING` per item and exits 1 if anything required is missing. It installs nothing.
- If packages are missing, prefer an isolated environment in the skill folder: `python3 -m venv .venv && . .venv/bin/activate && python -m pip install -r scripts/requirements.txt && python scripts/check_setup.py` (`make-audiobook.sh` uses that `.venv` automatically). Only fall back to `--break-system-packages` if the user agrees. `ffmpeg`/`ffprobe` cannot come from pip: tell the user to install them (`apt install ffmpeg`, `brew install ffmpeg`).
- Server reachability: `GET <url>/v1/audio/voices`. The workspace network is often restricted and a home-lab server may be unreachable. If the request is refused or times out, do not retry other routes. Prepare everything up to the final command and give the user the exact command to run where the server is reachable, or use a shell on their computer if one is linked.

## 3. Find the unknown words (phase 1)

```bash
scripts/make-audiobook.sh "<epub>" <slug> --glossary glossaries/<series>.csv
```

This writes `<outdir>/<slug>_work/words.csv` and stops. If it already exists, keep it (use `--refresh` only if the user asks, because it overwrites their work). Read the list. Rare but real English words (archaic or technical terms) usually need no change; names, places and invented terms are the focus.

## 4. Fill in pronunciations

Work from the most to the least frequent word.

- Use the user's book context first, then the series glossary (skip words it already covers), then web search for each uncertain name (for example `how to pronounce <name> <series>`), preferring official audiobook narrators, publishers, the author, and trusted wikis. Never invent a pronunciation. If sources disagree or none exist, mark the word uncertain and ask.
- Write a respelling a text-to-speech model reads naturally: lowercase syllables joined by hyphens, with doubled vowels or a familiar word to carry the sound (for example `Er-zuh`, `Toe-kay-zhuh`). Avoid symbols and capitals inside a word. Use `[word](/phonemes/)` markup only if the user asks and the server handles it.
- Leave `pronunciation` blank for words that already sound right. Keep the header `word,count,pronunciation` and the exact casing from the book (replacement is whole-word and case-sensitive). Add multi-word names as their own rows.

Show the user a compact table of word → respelling, with uncertain entries marked and the source for each, and ask them to confirm or correct before synthesis. Save their corrections into `words.csv`.

Optional spot check when the server is reachable:

```bash
python scripts/test_pronunciation.py --pronunciations <slug>_work/words.csv --max 10 --fx
```

It writes each word as written and respelled into the OS temp folder (`python scripts/resources.py tests` prints it; the OS cleans it up eventually, so send the clips now); send the clips to the user and adjust.

To check a whole glossary by ear: `python scripts/test_glossary.py <glossary>` (renders as-written and respelled clips into one review file),
then the user runs `python scripts/review_pronunciations.py <glossary>` in a terminal. It plays each pair, asks which sounds best
(1, 2, or r to repeat) and updates the glossary and moves decided clips into `clips/reviewed/` (ignored afterwards); picking Kokoro's own pronunciation leaves the second column blank, and blank
rows are never respelled. `scripts/play_audio.py FILE` plays any clip on Linux, macOS or Windows.

## 5. Convert (phase 2)

Preview the sections first and check that the prologue, chapters and epilogue are present and the front and back matter is skipped:

```bash
scripts/make-audiobook.sh "<epub>" <slug> --list
```

Then run the same wrapper command again (with `--url` or `KOKORO_URL`, the glossary, and any `-- --tempo X --voice Y` settings):

```bash
scripts/make-audiobook.sh "<epub>" <slug> --glossary glossaries/<series>.csv --url <url> -- --tempo 0.9
```

- It is long-running (large books take many minutes to hours). Run it in the background or with a long timeout and check progress. It prints timestamped, flushed progress (per chunk, per chapter, with an ETA) and also writes `<slug>_work/chapters/convert.log` (override with `-- --log FILE`); `tail -f` that file.
- It is resumable: finished chapters are skipped and in-progress chunks reused, so rerun the same command after an interruption.
- New pronunciations only affect chapters generated afterwards. To redo a chapter, delete its `<slug>_work/chapters/chapter_XX.flac` and rerun.
- If the server rejects the voice, rerun with `-- --voice am_onyx`. If synthesis keeps failing, report the server's error instead of looping.

## 6. Finish

- Send the finished `.m4b` and the final `words.csv` with SendUserFile. If the file is too large to send, say where it is.
- Tell the user where the working files are (`<outdir>/<slug>_work/`) and keep them: if they are unhappy with the result, change `words.csv`, delete just the affected `chapters/chapter_XX.flac` files, and rerun the same command; every other chapter is reused.
- Offer to save the new pronunciations for the next book in the series: `python scripts/update_glossary.py <slug>_work/words.csv glossaries/<series>.csv`.
- Summarize in two or three lines: sections read, pronunciations applied, and any words left uncertain.
- End with a "Sources:" list of the pages used to confirm pronunciations, as markdown links.

## Troubleshooting and exit codes

Every script exits 0 on success and non-zero on failure, with a one-line reason on stderr; none of them deletes or overwrites a finished chapter.

| Message | Meaning and fix |
|---|---|
| `Missing Python package 'X'` | Install requirements (step 2), then rerun. |
| `'ffmpeg' was not found on PATH` | Install ffmpeg; it includes ffprobe. |
| `Epub not found` / `Could not read ... as an epub` | Wrong path, a corrupt file, or DRM. Ask the user for another copy. |
| `Invalid server URL` / `No server URL` | Needs `--url` or `KOKORO_URL` starting with `http://` or `https://`. |
| `Giving up on a chunk after repeated failures` | The server is unreachable or erroring; report its message, do not loop. Rerun later: finished chunks are reused. |
| `The server rejected the voice` | Rerun with `-- --voice am_onyx`. |

Expected output of a successful run: `<outdir>/<slug>.m4b` (one file, one chapter marker per section; verify with `ffprobe -show_chapters`) and `<outdir>/<slug>_work/` with `words.csv`, `chapters/` and `convert.log`.

## Principles

- Ask for context and server details up front; do not run the pipeline on assumptions.
- Never fabricate a pronunciation. Say "uncertain" and let the user decide.
- Do not commit or share the user's server URL or the epub itself beyond this task.
