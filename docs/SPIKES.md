# Bardoro embedded-engine spikes (phase 0b)

Companion to `FLUTTER_CONVERSION.md` §11 and §6.5b. Five time-boxed experiments that decide whether the embedded Kokoro engine is viable on Windows, macOS and Linux **before** you build the app. Each one has exact steps, a pass/fail rule, and a row in the results table at the end. Do them in order; S1 gates the rest.

Suggested time box: one day each, S3 two days. Stop a spike early the moment its fail rule triggers, and write down why.

## 0. One-time setup

### 0.1 Pinned assets (verified in a sandbox)

| File | Bytes | SHA-256 |
|---|---|---|
| `kokoro-v1.0.onnx` | 325,532,387 | `7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5` |
| `voices-v1.0.bin` (npz, 54 voices, each `(510,1,256)`) | 28,214,398 | `bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d` |

```bash
mkdir -p assets && cd assets
BASE=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
curl -LO $BASE/kokoro-v1.0.onnx
curl -LO $BASE/voices-v1.0.bin
sha256sum kokoro-v1.0.onnx voices-v1.0.bin      # macOS: shasum -a 256 ...
```

Model I/O (verified): inputs `tokens` int64 `[1,N]`, `style` float32 `[1,256]`, `speed` float32 `[1]`; output `audio` float32 1-D at 24,000 Hz. Read the names from the session at runtime anyway.

### 0.2 Python reference environment

Python 3.10+ (tested on 3.13). Keep it outside the repo.

```bash
python -m venv .spike-venv && source .spike-venv/bin/activate   # Windows: .spike-venv\Scripts\activate
pip install kokoro-onnx==0.6.1 soundfile numpy
```

### 0.3 Generate reference data

Save as `tools/spikes/make_reference.py` (or anywhere) and run `python make_reference.py assets spike-ref`.

```python
#!/usr/bin/env python3
"""Write reference tokens, style rows and audio for spike S1. Usage: make_reference.py ASSETS_DIR OUT_DIR"""
import json, sys, numpy as np, soundfile as sf
from pathlib import Path
from kokoro_onnx import Kokoro
from kokoro_onnx.tokenizer import Tokenizer
assets, out = Path(sys.argv[1]), Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
k = Kokoro(str(assets/"kokoro-v1.0.onnx"), str(assets/"voices-v1.0.bin")); tok = Tokenizer()
voices = np.load(assets/"voices-v1.0.bin")
cases = {"short": "The name Urza echoed through the hall.",
         "numbers": "Chapter 12 began at dawn, and 1,200 soldiers marched.",
         "long": " ".join(["The wind carried the smell of rain across the valley, and nobody spoke."]*6)}
meta = []
for name, text in cases.items():
    ph = tok.phonemize(text); ids = tok.tokenize(ph)
    row = voices["am_onyx"][min(len(ids), 510) - 1][0]
    audio, sr = k.create(text, voice="am_onyx", speed=1.0, lang="en-us")
    sf.write(out/f"{name}.ref.wav", audio, sr)
    (out/f"{name}.tokens.json").write_text(json.dumps([0, *ids, 0]))
    row.astype("<f4").tofile(out/f"{name}.style.f32")
    meta.append({"name": name, "text": text, "phonemes": ph, "n_tokens": len(ids), "ref_seconds": len(audio)/sr})
(out/"reference.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))
print(json.dumps(meta, indent=2, ensure_ascii=False))
```

Expected output from the sandbox run (your numbers should match exactly for tokens; durations within a few ms):

| case | tokens | reference seconds |
|---|---|---|
| short | 36 | 2.859 |
| numbers | 82 | 4.736 |
| long | 443 | 20.608 |

The `short` phonemes should be `ðə nˈeɪm ˈɜːzə ˈɛkoʊd θɹuː ðə hˈɔːl.` Note that espeak-ng alone expands "12" and "1,200" to words ("twˈɛlv", "wˈʌn θˈaʊzənd tˈuːhˈʌndɹɪd"), which is useful for S3/S5.

Each case writes `NAME.tokens.json` (already padded with 0 at both ends), `NAME.style.f32` (256 little-endian floats) and `NAME.ref.wav`.

---

## S1. Run the model through `flutter_onnxruntime` on all three OSes

**Question:** does the Kokoro v1.0 model load and produce correct audio on Windows, macOS and Linux from Dart?

**Setup**
```bash
flutter create --platforms=windows,macos,linux spike_s1 && cd spike_s1
flutter pub add flutter_onnxruntime path_provider
```
macOS: set the deployment target to 14.0 (package minimum) in `macos/Podfile` and the Xcode project; add the network-client/file entitlements you need. Copy `assets/*.onnx` somewhere on disk (don't bundle 325 MB as a Flutter asset; load by path), and copy `spike-ref/*` next to it.

**Steps**
1. In a tiny CLI-style `main`, create the session from the model file path; print `getInputNames()`, `getOutputNames()` and each input's type.
2. Read `short.tokens.json` and `short.style.f32`; build `tokens` as int64 `[1,N]`, `style` float32 `[1,256]`, `speed` float32 `[1]` = 1.0. Run.
3. Write the output as a 16-bit WAV (24 kHz mono) and listen. Repeat for `numbers` and `long`.
4. Compare to `*.ref.wav`: sample count should be within 1% of the reference, and peak amplitude within 10%. Quick check: `ffprobe -v error -show_entries format=duration -of csv=p=0 out.wav`.
5. Style row experiment: also run `short` with the row at index `len(tokens)` (the model card's convention) instead of `len-1`. Listen to both. Record which sounds better or whether you can tell.
6. Repeat on Windows, macOS and Linux (a VM or CI runner is fine for load success; listen on real hardware).

**Pass:** all three OSes load the model, names/dtypes match, output duration within 1% of reference, speech intelligible with no clicks or garbling.
**Fail:** any OS cannot load the model or crashes (try `onnxruntime_v2`, or FFI to the ONNX Runtime C API, and re-run). If neither works on an OS, the embedded engine is a no-go there.

## S2. Real-time factor (speed)

**Question:** how long does a full book take, and does anything beat plain CPU?

**Steps**
1. In the S1 project add a timer around `session.run` only (not tokenization). Run the `long` case 5 times; discard the first (warm-up). Record median seconds and RTF = audio seconds ÷ wall seconds (higher is faster).
2. Do this on each OS, on your slowest machine you care about.
3. Try thread settings if the plugin exposes them (intra-op threads = physical cores, then half).
4. Try execution providers per OS: Windows DirectML, macOS CoreML, Linux CPU only (or CUDA if present). Record RTF and **listen**: some providers change output quality or fail on this model.
5. Try an int8 or fp16 model variant (published separately by the kokoro-onnx project and onnx-community; record the file name, size and hash you used). fp16 support is incomplete on Linux/Windows CPU in `flutter_onnxruntime`; note failures.
6. Book estimate: `hours = (words ÷ 150) ÷ 60 ÷ RTF`. A 100,000-word novel is about 11 hours of speech.

**Reference point:** in a 2-CPU sandbox with Python onnxruntime fp32, a 4.5 s clip took 3.7 s (RTF about 1.2). Expect a modern laptop to do clearly better; treat this number as a floor.

**Pass:** RTF ≥ 2 on your slowest target (a novel in about 5 h or less, running unattended), and you have a default (fp32 or int8, CPU or provider) with notes on quality.
**Fail:** RTF < 1 on CPU and no provider helps. Mitigation: keep `KokoroHttpEngine` as the default and ship embedded as "slow mode".

## S3. G2P approach and unresolved-word rate

**Question:** which phonemizer strategy do you ship, and what share of words fails?

**Options to compare**
- A. **espeak-ng only** (what kokoro-onnx does). Simplest. Gets rough number/abbreviation expansion.
- B. **Dictionary + rules** (malsami or your own port of misaki's lexicon) with espeak fallback.
- C. Dictionary + rules only (no espeak): measure how many words are unresolved.

**Steps**
1. Pick 3 real books (a modern novel, a fantasy with invented names, a non-fiction). Extract text using your Dart `extract_sections` port, or Python's `epub_to_kokoro.extract_sections` for now.
2. Build the word list: lowercase unique words with counts.
3. Run each option over the list and count: resolved, unresolved, and unresolved weighted by occurrences. Python helper for the baseline:
   ```python
   from kokoro_onnx.tokenizer import Tokenizer
   tok = Tokenizer(); print(tok.phonemize("Tocasia"))
   ```
4. If you have a Kokoro-FastAPI server, ground-truth against it: `POST <url>/dev/phonemize` with `{"text": "...", "language": "a"}` and diff the phoneme strings for 200 random sentences. Record exact-match % and the most common differences. (Endpoint path is from the FastAPI README; confirm on your server version.)
5. Listen to 20 sentences with invented names rendered via option A and via your pronunciation respellings (`Er-zuh`) to check respellings still work when espeak phonemizes them.

**Pass:** an approach where unresolved words (weighted) are under 1% of the book, respellings behave as in the HTTP path, and sentence-level phoneme match to the server is ≥ 90% (or the differences are inaudible in your A/B).
**Fail:** A is audibly worse than the server on names and B has a high unresolved rate. Fallback: bundle espeak-ng (S5) and require it for every word.

## S4. A/B a real chapter: embedded vs server

**Question:** would a listener notice a difference?

**Steps**
1. Choose one chapter (~3,000 words) from S3's novel. Run it through the current Python pipeline against your Kokoro server (same voice blend, same glossary, tempo 0.90, deep-voice filter) to get `server.flac`.
2. Produce `embedded.flac` with your prototype: same text prep, chunking at 2,500 characters, phonemize, split at 510 phonemes, infer, trim and add pauses (0.25 s after sentences, 0.1 s after clauses, as kokoro-onnx does), then the same ffmpeg filter.
   - Voice blend `am_onyx(4)+am_adam(1)`: weighted average of the two style rows `(4*onyx + 1*adam)/5` per row index.
3. Compare objectively: durations, loudness (`ffmpeg -i X -af ebur128 -f null -`), and silence-gap histogram (`ffmpeg -i X -af silencedetect=n=-40dB:d=0.1 -f null -`).
4. Compare subjectively: blind-listen to 10 random 30 s clips per file, 3 listeners if possible. Note seams between chunks, pace, mispronounced numbers/names.

**Pass:** duration within 5%, integrated loudness within 1.5 LU, and blind listeners pick the right one no more than chance (about 50-60%) or call differences minor.
**Fail:** audible seams, clipped word ends (trim too aggressive), or flat pacing. Adjust trim threshold and pauses, retry once, then decide.

## S5. Bundle espeak-ng on all three OSes

**Question:** can you ship espeak-ng (GPL, which matches your license) reliably, and what does it cost?

**Steps**
1. Reference sizes from `espeakng-loader` 0.2.4: Linux `libespeak-ng.so` is about 0.66 MB, `espeak-ng-data` about 19 MB. Do the same for Windows and macOS wheels (`pip download espeakng-loader --platform win_amd64 --only-binary=:all:`; unzip and measure).
2. **Subprocess route:** ship `espeak-ng` binary + data per OS; run `espeak-ng -q --ipa=3 -v en-us "text"`; check it with your app's sandbox/permissions. Measure the time for 1,000 words one call per word vs one call for a sentence batch.
3. **FFI route:** `dart:ffi` to `libespeak-ng` (`espeak_Initialize`, `espeak_TextToPhonemes`). Process-global state, so serialize calls, same as kokoro-onnx's lock. Measure the same workload.
4. Map espeak IPA to Kokoro's vocabulary: drop any character not in `config.json` `vocab` (114 symbols) as kokoro-onnx does; log the distinct dropped characters.
5. Unresolved-word rate (S3's list) with and without espeak; speed cost per 100,000 words.
6. Licensing check: put the espeak-ng license text in `assets/licenses/` and add it to the About screen; record version and source URL.

**Pass:** works on all 3 OSes in a packaged build (not just `flutter run`), cost under 2% of total synthesis time, and the packaged installer grows by under about 25 MB.
**Fail:** cannot load in the packaged build on an OS (signing/notarization on macOS is the usual cause). Fallback: subprocess route, or drop espeak and accept a higher unresolved-word rate.

---

## Go / no-go

Go if S1 passes on all 3 OSes, S2 gives RTF ≥ 2 on your slowest target (or you accept "slow mode"), S3/S5 yield <1% unresolved words, and S4 passes. Otherwise ship `KokoroHttpEngine` first and keep the embedded engine behind a setting until the failed spike is fixed.

## Results table (fill in)

| Spike | Windows | macOS | Linux | Date | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| S1 loads and plays | | | | | | |
| S1 style row (len vs len-1) | | | | | | |
| S2 RTF fp32 CPU | | | | | | |
| S2 RTF int8 / provider | | | | | | |
| S2 full-book estimate (words / hours) | | | | | | |
| S3 unresolved words, option A | | | | | | |
| S3 unresolved words, option B | | | | | | |
| S3 phoneme match vs server (%) | | | | | | |
| S4 duration diff / LU diff / blind result | | | | | | |
| S5 bundle works in packaged build | | | | | | |
| S5 installer size added / speed cost | | | | | | |
| **Decision** | | | | | | |
