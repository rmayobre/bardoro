"""
Startup checks shared by the scripts: friendly, actionable errors instead of tracebacks.

  require("bs4", "beautifulsoup4")   import a third-party module or exit with install instructions
  need_binary("ffmpeg")              exit with install hints if an external program is not on PATH
  check_python()                     exit if Python is older than MIN_PYTHON

This file uses only the standard library, so it can always be imported. Every failure exits with status 1 and a
message on stderr; nothing is installed or changed.
"""
import importlib
import shutil
import sys
from pathlib import Path

MIN_PYTHON = (3, 9)
REQUIREMENTS = Path(__file__).resolve().parent / "requirements.txt"

_INSTALL_HINTS = {
    "ffmpeg": "Linux: sudo apt install ffmpeg | macOS: brew install ffmpeg | Windows: winget install ffmpeg",
    "ffprobe": "ffprobe ships with ffmpeg; install ffmpeg (see above)",
}


def check_python():
    if sys.version_info < MIN_PYTHON:
        have = ".".join(map(str, sys.version_info[:3]))
        sys.exit(f"Python {'.'.join(map(str, MIN_PYTHON))}+ is required, but this is Python {have}. "
                 "Use a newer interpreter, for example: python3.11 -m venv .venv")


def require(module, package=None):
    """Import and return `module`; exit with install instructions if it is missing."""
    try:
        return importlib.import_module(module)
    except ImportError:
        sys.exit(f"Missing Python package '{package or module}' (needed to import '{module}').\n"
                 f"Install everything in a virtual environment with:\n"
                 f"  python3 -m venv .venv && . .venv/bin/activate    (Windows: .venv\\Scripts\\activate)\n"
                 f"  python -m pip install -r \"{REQUIREMENTS}\"")


def need_binary(name):
    """Exit with install hints unless `name` is on PATH. Returns its full path."""
    found = shutil.which(name)
    if not found:
        sys.exit(f"'{name}' was not found on PATH. {_INSTALL_HINTS.get(name, 'Install it and try again.')}")
    return found
