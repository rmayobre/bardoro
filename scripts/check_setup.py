#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["ebooklib>=0.18,<1", "beautifulsoup4>=4.12,<5", "pyspellchecker>=0.8,<1"]
# ///
"""
Check that this machine can run the Bardoro scripts. Changes nothing and sends nothing unless you ask for the
server check.

  python check_setup.py                       Python version, the three Python packages, ffmpeg and ffprobe
  python check_setup.py --url http://host:8880    also ask the Kokoro server for its voices (one GET request)
  python check_setup.py --check-server        same, using $KOKORO_URL

Exit status: 0 when everything checked is fine, 1 when anything required is missing or unreachable.
"""
import argparse
import importlib
import importlib.metadata
import json
import os
import shutil
import subprocess
import sys
import urllib.request

MIN_PYTHON = (3, 9)
PACKAGES = [("ebooklib", "ebooklib"), ("bs4", "beautifulsoup4"), ("spellchecker", "pyspellchecker")]


def check_python():
    have = ".".join(map(str, sys.version_info[:3]))
    ok = sys.version_info >= MIN_PYTHON
    print(f"{'ok     ' if ok else 'MISSING'} Python {have} (need {'.'.join(map(str, MIN_PYTHON))}+)")
    return ok


def check_packages():
    ok = True
    for module, package in PACKAGES:
        try:
            importlib.import_module(module)
            try:
                version = importlib.metadata.version(package)
            except importlib.metadata.PackageNotFoundError:
                version = "?"
            print(f"ok      {package} {version}")
        except ImportError:
            ok = False
            print(f"MISSING {package}")
    if not ok:
        print("        fix: python -m pip install -r scripts/requirements.txt   (inside a virtual environment)")
    return ok


def check_binary(name):
    path = shutil.which(name)
    if not path:
        print(f"MISSING {name}  (Linux: sudo apt install ffmpeg | macOS: brew install ffmpeg | "
              "Windows: winget install ffmpeg)")
        return False
    try:
        first = subprocess.run([path, "-version"], capture_output=True, text=True, timeout=20).stdout.splitlines()[0]
    except (OSError, subprocess.SubprocessError, IndexError):
        first = path
    print(f"ok      {first}")
    return True


def check_server(url):
    url = url.rstrip("/")
    if not url.lower().startswith(("http://", "https://")):
        print(f"MISSING server URL {url!r} must start with http:// or https://")
        return False
    try:
        with urllib.request.urlopen(f"{url}/v1/audio/voices", timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
        voices = data.get("voices", data) if isinstance(data, dict) else data
        print(f"ok      Kokoro server answered at {url} ({len(voices)} voices)")
        return True
    except Exception as e:  # any failure means "not usable from here"; the message says why
        print(f"MISSING Kokoro server at {url}: {e}")
        return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", help="Kokoro-FastAPI base URL to test")
    ap.add_argument("--check-server", action="store_true", help="test $KOKORO_URL")
    args = ap.parse_args()

    results = [check_python(), check_packages(), check_binary("ffmpeg"), check_binary("ffprobe")]
    url = args.url or (os.environ.get("KOKORO_URL") if args.check_server else None)
    if args.check_server and not url:
        print("MISSING KOKORO_URL is not set (or pass --url)")
        results.append(False)
    elif url:
        results.append(check_server(url))
    print("\nAll good." if all(results) else "\nSetup is incomplete; see the lines marked MISSING.")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
