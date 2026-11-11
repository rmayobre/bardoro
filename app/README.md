# Bardoro desktop app

Flutter desktop front end for Bardoro (Linux, macOS, Windows). It contains UI and state only; the work happens in
local packages:

| Package | Role |
|---|---|
| `packages/bardoro_core` | Pure Dart: epub, text, glossaries, ffmpeg, the resumable `PipelineRunner`. |
| `packages/bardoro_services` | App services: settings, library scan, `BookAnalyzer`, `JobBuilder`, `ConversionSession`. |
| `packages/bardoro_kokoro_local` | Embedded Kokoro engine (skeleton until the spikes pass). |

## How volley and zero_nads are used

* **volley** keeps the UI isolate free. Epub analysis runs in a `coroutine()`; a conversion runs in an `actor()`
  (`conversionReducer`). An actor handles one message at a time, so the reducer returns immediately: the pipeline runs
  on that isolate's event loop and the UI polls it (`PollConversion`) and cancels it (`CancelConversion`).
* **zero_nads** structures the code: lazy `Task`s for IO, `Result` for failures that the UI shows instead of
  throwing, `Option` for "no server URL yet", and `Snapshot` for every observable (`SnapshotBuilder` rebuilds
  widgets from one).

## Layout

```
lib/main.dart, app.dart     start-up (volley Bootstrapper) and the MaterialApp
lib/state/                  AppController (settings, library) and BookController (one book's wizard)
lib/ui/                     shell, library, settings, and the wizard steps (sections, words, voice, convert)
lib/platform/               things that need the OS (open the file manager)
assets/seed/                starter voice profiles and glossaries, copied into a new workspace
integration_test/           the real app converting an epub against a fake Kokoro server
```

## Run and test

```bash
flutter pub get             # from the repo root: it is a Dart workspace
flutter run -d linux        # macos, windows
flutter test
xvfb-run -a flutter test integration_test -d linux     # headless Linux; needs ffmpeg and ffprobe
```

macOS: the app sandbox is off (it runs ffmpeg and reads your workspace) and `network.client` is on; both are in the
entitlements files. GUI apps do not see Homebrew's `PATH`, so set the full ffmpeg path in Settings.
