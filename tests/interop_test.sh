#!/usr/bin/env bash
# Checks that the Dart pipeline (packages/bardoro_core) and the Python CLI can finish each other's books:
# same workspace layout, same resume markers, same voice_settings.json. Uses the fake Kokoro server (no real TTS).
#
# usage: tests/interop_test.sh          (needs: tools/requirements.txt deps, ffmpeg/ffprobe, dart)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.venv/bin/activate" ] && source "$ROOT/.venv/bin/activate"
TMP="$(mktemp -d)"; PORT=18998
trap 'kill $SERVER_PID 2>/dev/null || true; rm -rf "$TMP"' EXIT

python - "$TMP" <<'PY'
import sys
from ebooklib import epub
b = epub.EpubBook(); b.set_identifier("interop"); b.set_title("Interop"); b.set_language("en")
chapters = []
for i, body in enumerate([
    "<h1>Prologue</h1><p>Urza waited. Tocasia nodded, and the night was quiet.</p>",
    "<h1>Chapter 1</h1><p>Urza's brother Mishra arrived. " + "They spoke at length. " * 40 + "</p>",
    "<h1>Chapter 2</h1><p>" + "More talk followed in the hall. " * 200 + "</p>",
    "<h1>Epilogue</h1><p>Mishra remembered everything.</p>"], 1):
    c = epub.EpubHtml(title=f"c{i}", file_name=f"c{i}.xhtml", lang="en"); c.content = body
    b.add_item(c); chapters.append(c)
b.spine = chapters; b.add_item(epub.EpubNcx()); b.add_item(epub.EpubNav())
epub.write_epub(f"{sys.argv[1]}/The Brothers' War - Interop (2000).epub", b)
PY
EPUB="$TMP/The Brothers' War - Interop (2000).epub"
printf 'word,pronunciation\nMishra,Mish-ruh\nUrza,Er-zuh\n' > "$TMP/gloss.csv"
python "$ROOT/tests/fake_kokoro_server.py" $PORT "$TMP/requests.log" & SERVER_PID=$!
sleep 1
export KOKORO_URL="http://127.0.0.1:$PORT"
BARDORO=(dart run "$ROOT/packages/bardoro_core/bin/bardoro.dart")
PYCONV=(python "$ROOT/tools/epub_to_kokoro.py" "$EPUB" --pronunciations "$TMP/gloss.csv")

echo "== Dart converts a whole book; the Python CLI then resumes it without a single request"
"${BARDORO[@]}" convert "$EPUB" --pronunciations "$TMP/gloss.csv" --work "$TMP/a/chapters" --out "$TMP/a/book.m4b" >/dev/null
[ "$(ffprobe -v error -show_chapters -of csv=p=0 "$TMP/a/book.m4b" | wc -l)" -eq 4 ]
grep -q "Er-zuh" "$TMP/requests.log" && ! grep -q "Urza" "$TMP/requests.log"
N1=$(wc -l < "$TMP/requests.log")
"${PYCONV[@]}" --work "$TMP/a/chapters" --out "$TMP/a/book2.m4b" > "$TMP/py_resume.out"
N2=$(wc -l < "$TMP/requests.log")
[ "$N1" -eq "$N2" ] || { echo "Python re-requested chapters Dart had finished"; exit 1; }
grep -q "WARNING: voice settings differ" "$TMP/py_resume.out" && { echo "Python flagged Dart's voice_settings.json as different"; cat "$TMP/py_resume.out"; exit 1; }
[ "$(ffprobe -v error -show_chapters -of csv=p=0 "$TMP/a/book2.m4b" | wc -l)" -eq 4 ]

echo "== Python converts; delete the last chapter; Dart finishes only that one"
mkdir -p "$TMP/b"; "${PYCONV[@]}" --work "$TMP/b/chapters" --out "$TMP/b/book.m4b" >/dev/null
rm "$TMP/b/chapters/chapter_04.flac" "$TMP/b/book.m4b"
N1=$(wc -l < "$TMP/requests.log")
"${BARDORO[@]}" convert "$EPUB" --pronunciations "$TMP/gloss.csv" --work "$TMP/b/chapters" --out "$TMP/b/book.m4b" > "$TMP/dart_resume.out"
N2=$(wc -l < "$TMP/requests.log")
[ $((N2 - N1)) -eq 1 ] || { echo "expected exactly 1 request to redo chapter 4, got $((N2 - N1))"; exit 1; }
grep -q "WARNING: voice settings differ" "$TMP/dart_resume.out" && { echo "Dart flagged Python's voice_settings.json as different"; exit 1; }
[ "$(ffprobe -v error -show_chapters -of csv=p=0 "$TMP/b/book.m4b" | wc -l)" -eq 4 ]

echo "== a Python-written chunk is reused by Dart (interrupted run)"
mkdir -p "$TMP/c/chapters"
ffmpeg -v error -f lavfi -i sine=frequency=220:duration=0.5 -ar 24000 "$TMP/c/chapters/chapter_01_part_001.flac"
N1=$(wc -l < "$TMP/requests.log")
"${BARDORO[@]}" convert "$EPUB" --pronunciations "$TMP/gloss.csv" --work "$TMP/c/chapters" --out "$TMP/c/book.m4b" > "$TMP/dart_chunk.out"
grep -q "chunk 1/1: reusing existing file" "$TMP/dart_chunk.out" || { echo "Dart did not reuse the existing chunk"; exit 1; }
N2=$(wc -l < "$TMP/requests.log")
[ $((N2 - N1)) -eq 5 ] || { echo "expected 5 requests (chapter 2: 1 chunk, chapter 3: 3 chunks, chapter 4: 1), got $((N2 - N1))"; exit 1; }

echo "== the Dart word finder writes the same words.csv as the Python one"
python "$ROOT/tools/find_unknown_words.py" "$EPUB" --out "$TMP/py_words.csv" >/dev/null
"${BARDORO[@]}" words "$EPUB" --out "$TMP/dart_words.csv" >/dev/null
cmp "$TMP/py_words.csv" "$TMP/dart_words.csv" || { echo "words.csv differs"; exit 1; }

echo "INTEROP OK"
