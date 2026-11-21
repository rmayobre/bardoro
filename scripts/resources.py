"""
Find glossaries, voice profiles and epubs in two places: the current directory (yours) and the skill directory
(shared, ships with the skill). The current directory is searched first, so a local file wins over a shared one with
the same name.

  glossaries   ./glossaries/NAME.csv, then <skill>/glossaries/NAME.csv   (or any path that exists)
  voices       ./voices/NAME.json,    then <skill>/voices/NAME.json      (or any path to a .json file)
  epubs        the path as given, then ./NAME, ./NAME.epub, ./books/NAME, ./books/NAME.epub

Command line (used by make-audiobook.sh):
  python resources.py glossary NAME      print the path of a glossary, exit 1 if not found
  python resources.py epub NAME          print the path of an epub, exit 1 if not found
  python resources.py epubs              list the .epub files in ./ and ./books
  python resources.py where              show the folders searched
"""
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent


def search_dirs(kind):
    """[./kind, <skill>/kind] with duplicates removed (they are the same folder when run from the skill itself)."""
    out, seen = [], set()
    for base in (Path.cwd(), SKILL_DIR):
        d = (base / kind).resolve()
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def _find(kind, name, suffix):
    p = Path(name)
    if p.is_file():
        return p
    for d in search_dirs(kind):
        for cand in (d / name, d / f"{name}{suffix}"):
            if cand.is_file():
                return cand
    return None


def find_glossary(name):
    return _find("glossaries", name, ".csv")


def find_voice(name):
    return _find("voices", name, ".json")


def find_epub(name):
    for base in (Path("."), Path("books")):
        for cand in (base / name, base / f"{name}.epub"):
            if cand.is_file():
                return cand
    return None


def list_epubs():
    return sorted(p for d in (Path("."), Path("books")) for p in d.glob("*.epub"))


def list_files(kind, pattern):
    """[(path, 'local' or 'skill')] for every match, local first; a local file hides a skill file of the same name."""
    seen, out = set(), []
    for d in search_dirs(kind):
        origin = "local" if d.parent == Path.cwd().resolve() else "skill"
        for f in sorted(d.glob(pattern)):
            if f.name not in seen:
                seen.add(f.name)
                out.append((f, origin))
    return out


def main():
    cmd, rest = (sys.argv[1] if len(sys.argv) > 1 else ""), sys.argv[2:]
    if cmd in ("glossary", "epub") and rest:
        found = (find_glossary if cmd == "glossary" else find_epub)(rest[0])
        if not found:
            sys.exit(1)
        print(found)
    elif cmd == "epubs":
        for p in list_epubs():
            print(p)
    elif cmd == "where":
        for kind in ("glossaries", "voices"):
            print(f"{kind}: " + ", ".join(str(d) for d in search_dirs(kind)))
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
