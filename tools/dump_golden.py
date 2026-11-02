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
