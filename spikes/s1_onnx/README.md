# Spikes S1 and S2: Kokoro through `flutter_onnxruntime`

Harness for `docs/SPIKES.md` S1 (does the model load and produce correct audio on this OS?) and S2 (real-time
factor). It runs once, prints `RESULT {json}`, writes `results.json` and WAV files, and exits. Nothing here has
been run against the real model yet: only the build on Linux and the file-parsing unit tests (`flutter test`) were
checked. The plugin API calls were written from `flutter_onnxruntime` 1.9.0's published source.

## 1. Reference data (once, any machine; needs Python 3.10+)

From the repo root. `make_reference.py` is the script from SPIKES.md §0.3 (it sits untracked at the repo root).

```bash
python -m venv .spike-venv && source .spike-venv/bin/activate        # Windows: .spike-venv\Scripts\activate
pip install kokoro-onnx==0.6.1 soundfile numpy
mkdir -p assets && cd assets
BASE=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
curl -LO $BASE/kokoro-v1.0.onnx && curl -LO $BASE/voices-v1.0.bin
sha256sum kokoro-v1.0.onnx voices-v1.0.bin                           # macOS: shasum -a 256
cd .. && python make_reference.py assets spike-ref
```

Expected SHA-256 (SPIKES.md §0.1): model `7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5`,
voices `bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d`. Expected token counts 36 / 82 / 443 and
reference seconds 2.859 / 4.736 / 20.608. Copy `assets/` and `spike-ref/` to the other machines (they are git-ignored).

## 2. Run S1 + S2 (on each OS)

```bash
cd spikes/s1_onnx
flutter create --platforms=linux,macos,windows --project-name spike_s1_onnx .   # generates the runner folders (git-ignored)
```

macOS only: set the deployment target to 14.0 in `macos/Podfile` (`platform :osx, '14.0'`) and in the Xcode project,
and set `com.apple.security.app-sandbox` to `false` in `macos/Runner/DebugProfile.entitlements` so the app can read
the model from your folders.

Linux / macOS:

```bash
export SPIKE_MODEL="$PWD/../../assets/kokoro-v1.0.onnx"
export SPIKE_VOICES="$PWD/../../assets/voices-v1.0.bin"
export SPIKE_REF="$PWD/../../spike-ref"
export SPIKE_OUT="$PWD/../../spike-out/$(uname -s)-cpu"
flutter run -d linux        # or: -d macos
```

Windows (PowerShell):

```powershell
$env:SPIKE_MODEL = "$PWD\..\..\assets\kokoro-v1.0.onnx"
$env:SPIKE_VOICES = "$PWD\..\..\assets\voices-v1.0.bin"
$env:SPIKE_REF = "$PWD\..\..\spike-ref"
$env:SPIKE_OUT = "$PWD\..\..\spike-out\windows-cpu"
flutter run -d windows
```

S2 variants: set `SPIKE_THREADS` (physical cores, then half), `SPIKE_PROVIDER` (`coreml` on macOS, `directml` on
Windows, `cuda` if present) and `SPIKE_MODEL` to an int8/fp16 file, and give each run its own `SPIKE_OUT`. Use
`flutter run --release -d <os>` for the S2 numbers (debug builds are not representative).

## 3. Read the result

`results.json` holds `inputNames`/`outputNames`/`inputInfo` (expect `tokens` int64, `style` float32, `speed`
float32 and output `audio`), per case `durationDiffPercent` (pass: within 1%), `peakDiffPercent` (pass: within
10%), `silent`, and `s2.rtf` (pass: >= 2 on your slowest target). Listen to `SPIKE_OUT/*.len-1.wav` (row `len - 1`,
kokoro-onnx's convention) against `*.len.wav` (row `len`, the model card's convention) and to the reference
`spike-ref/*.ref.wav`. Intelligible speech without clicks is part of the pass rule and only you can judge it.

## 4. Results (fill in; mirrors SPIKES.md)

| Check | Windows | macOS | Linux |
|---|---|---|---|
| Model loads, names/dtypes as expected | | | |
| `short` / `numbers` / `long` duration diff % | | | |
| peak diff % | | | |
| Listened: intelligible, no clicks | | | |
| Better style row: `len` or `len - 1` (by ear) | | | |
| S2 fp32 CPU RTF (median of 4) | | | |
| S2 int8 / provider RTF + provider used | | | |
| Full-book estimate for your slowest machine (hours) | | | |
