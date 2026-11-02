# Third-party notices

Bardoro is licensed GPL-3.0-or-later (see `LICENSE`). This file lists components it uses or plans to bundle.
Entries marked *planned* are not yet in the code. Check each licence before a release; this is not legal advice.

| Component | Licence | Status |
|---|---|---|
| Kokoro-82M model (ONNX) | Apache-2.0 (upstream credits apply) | planned, downloaded on first run |
| espeak-ng | GPL-3.0-or-later (plus other notices in its tree) | planned, bundled |
| ONNX Runtime, `flutter_onnxruntime` | MIT | planned |
| misaki data | Apache-2.0 | planned, only if ported |
| pyspellchecker word list | check before release (see `docs/FLUTTER_CONVERSION.md` D5) | used in `bardoro_core` assets |
| ffmpeg | LGPL or GPL, depends on the build | called as an external program |
| Dart packages (`archive`, `xml`, `html`, `http`, `path`) | BSD-3-Clause / MIT, see each package | used |
