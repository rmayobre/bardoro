#!/usr/bin/env python3
"""Regenerate the golden fixtures the Dart parity tests read. Run from anywhere:

  .venv/bin/python packages/bardoro_core/test/golden/make_golden.py

It builds small SYNTHETIC epubs (original text, no copyrighted material), runs the Python tools in tools/ over them
(the behavioural reference) and records what they produce as JSON next to this file. Nothing in tools/ is modified.
"""
import csv
import io
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[3] / "tools"
sys.path.insert(0, str(TOOLS))

from ebooklib import epub  # noqa: E402

import epub_to_kokoro as k  # noqa: E402
import voice_profiles as vp  # noqa: E402

SENT = ["The wind carried the smell of rain across the valley.", "Urza Planeswalker watched the horizon in silence.",
        "Mishra's brother did not answer, and “nobody spoke,” he said.", "Rhûn was far, and Éowyn was farther.",
        "Terenas Menethil II ruled, but Henry VIII did not; see Part II and Chapter IV.", "St. Anselm lit a lamp \U0001F642 at dusk!"]


def prose(n_chars, paras=1, start=0):
    """Deterministic prose of about n_chars per paragraph."""
    out = []
    for p in range(paras):
        s, i = "", start + p
        while len(s) < n_chars:
            s += SENT[i % len(SENT)] + " "
            i += 1
        out.append(s.strip())
    return out


def para(*texts):
    return "".join(f"<p>{t}</p>" for t in texts)


def build_epub(name, docs, toc=None, nav=True, ncx=False):
    """docs: [(file_name, body_html)]. toc: [(file_name, title)] or nested via ('Section', ...) tuples (flat here)."""
    b = epub.EpubBook()
    b.set_identifier(name)
    b.set_title(name)
    b.set_language("en")
    items = []
    for fn, body in docs:
        c = epub.EpubHtml(title="", file_name=fn, lang="en")
        c.content = f"<html><body>{body}</body></html>"
        b.add_item(c)
        items.append(c)
    if toc:
        b.toc = [epub.Link(fn, t, fn.split(".")[0]) for fn, t in toc]
    b.spine = items
    if ncx:
        b.add_item(epub.EpubNcx())
    if nav:
        b.add_item(epub.EpubNav())
    path = HERE / f"{name}.epub"
    epub.write_epub(str(path), b)
    return path


def make_epubs():
    stray = '<p><a href="https://oceanofpdf.com"><i>OceanofPDF.com</i></a></p>'
    long_sentence_para = " ".join(prose(2700)[0].split(" ")[:430])  # one >2500 char paragraph, many sentences
    emoji_para = "\U0001F642 " * 40 + prose(2300)[0]
    basic = [
        ("cover.xhtml", "<h1>Cover</h1><p>x</p>"),
        ("toc.xhtml", "<h1>Contents</h1><p>Prologue</p><p>Chapter 1</p>"),
        ("copy.xhtml", "<p>Copyright © 2000. All rights reserved.</p>"),
        ("pro.xhtml", "<h1>Prologue</h1>" + para("Urza waited. Tocasia nodded, and the night was quiet.") + stray),
        ("c1.xhtml", "<h2>Chapter 1</h2>" + para(*prose(900, 3)) + para(long_sentence_para)),
        ("c2.xhtml", "<h2>CHAPTER TWO</h2><h3>The Return</h3>" + para(*prose(500, 4, 3)) + para(emoji_para)),
        ("short.xhtml", "<p>" + "A short unlabelled section. " * 5 + "</p>"),
        ("longplain.xhtml", "<p>" + "A long unlabelled section with enough text to be kept. " * 70 + "</p>"),
        ("inter.xhtml", "<h1>Interlude: The Lamp.</h1>" + para("Anselm lit the lamp.", *prose(300, 2))),
        ("nohead.xhtml", para("Chapter 3 begins here without any heading element.", *prose(400, 2))),
        ("epi.xhtml", "<h1>Epilogue</h1>" + para("Mishra remembered everything.")),
        ("about.xhtml", "<h1>About the Author</h1>" + para(*prose(600, 6))),
    ]
    build_epub("basic", basic, toc=[("pro.xhtml", "Prologue"), ("c1.xhtml", "Chapter 1")])

    img = [
        ("pref.xhtml", "<p>" + "The long road home. " * 200 + "</p>" + stray),
        ("book1.xhtml", "<h1>Book I</h1><h1>THE FIRST PART</h1><h1>(1-2 A.R.)</h1><p>An epigraph.</p>"),
        ("c01.xhtml", '<div><img alt="7" src="x.jpg"/></div>' + para(*prose(1300, 3)) + stray),
        ("c02.xhtml", '<div><img alt="" src="y.jpg"/></div>' + para(*prose(1300, 3, 2))),
        ("c03.xhtml", '<div><img alt="Chapter art" src="y.jpg"/><img alt="12" src="z.jpg"/></div>' + para(*prose(1300, 3, 1))),
        ("c04.xhtml", "<div><img alt='' src='y.jpg'/></div>" + para(*prose(1300, 3, 4))),
        ("c05.xhtml", "<div><img alt='' src='y.jpg'/></div>" + para(*prose(1300, 3, 5))),
        ("part2.xhtml", "<h1>Part 2</h1><h2>" + "A very long subtitle heading that runs well past sixty characters " + "</h2>" + para("Text.")),
        ("loud.xhtml", "<h1>CHAPTER THE HOLLOW KING</h1>" + para(*prose(400, 2))),
        ("empty.xhtml", "<h1>. Chapter</h1>" + para(*prose(200, 2))),
        ("loud2.xhtml", "<h1>Prelude</h1>" + para(*prose(50, 1))),
        ("dots.xhtml", "<h1>...</h1>" + para("Interlude " + prose(3100)[0])),
        ("lead.xhtml", "<h1>Chapter 9: The Gate. It opens.</h1>" + para(*prose(200, 2))),
    ]
    toc = [("pref.xhtml", "Preface: The Legacy"), ("c04.xhtml", "Chapter Four –(Rise of the Horde)"),
           ("c05.xhtml", "The Fifth Gate-(1-2 A.R.)")]
    build_epub("images", img, toc=toc)

    ncx_docs = [("n1.xhtml", '<div><img alt="" src="a.jpg"/></div>' + para(*prose(1500, 3))),
                ("n2.xhtml", "<h1>Chapter 2</h1>" + para(*prose(300, 2)))]
    build_epub("ncx_only", ncx_docs, toc=[("n1.xhtml", "The Opening")], nav=False, ncx=True)

    acc = [("a1.xhtml", "<h1>Prologue</h1>" + para("Rhûn rose over Rhûn. Éowyn spoke; Éowyn left. Rhûn again, Éowyn again.",
                                                  "Mishra's staff and Mishra again; Urza's cloak. Tocasia, Tocasia, Zxqvbn Zxqvbn.") +
                          para("The Orcs' camp, Urza\u2019s cloak, Zxqvbn-Tocasia (Mishra\u2019s), Infinity and inf and NaN; Kaladesh Kaladesh.",
                               "Pneumonoultramicroscopicsilicovolcanoconiosisxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx twice, " * 2,
                               "Hello <b>Ur</b><i>za</i> Ur<span>za</span> Ur&nbsp;za, don't won't it's Tocasia\u2014Mishra Kaladesh\u2010Urza."))]
    build_epub("accents", acc, toc=[])


def run_py(script, *args):
    r = subprocess.run([sys.executable, str(TOOLS / script), *map(str, args)], capture_output=True, text=True, cwd=TOOLS)
    if r.returncode:
        sys.exit(f"{script} failed: {r.stderr}")
    return r.stdout


def write_pron_files():
    d = HERE / "pron"
    d.mkdir(exist_ok=True)
    (d / "series.csv").write_text(
        "word,pronunciation\nUrza Planeswalker,Er-zuh Plan-ez-walker\nMishra,Mish-ruh\nKeepme,\nSt.,Saint\n"
        "Menethil II,Mah-neth-il the Second\nRhûn,Roon\nMa'at,Mah-aht\n\"Quoted, Name\",\"Say \"\"it\"\"\"\n", encoding="utf-8")
    (d / "book.csv").write_text("﻿Word,Count,Pronunciation\nUrza,412,Er-zuh\nTocasia,96,\nMishra,5,Mish-rah\n"
                                "Éowyn,3,Ay-oh-win\n", encoding="utf-8")
    (d / "extra.json").write_text(json.dumps({"Zxqvbn": "Zix-quib-in", "Blank": "", 5: 7, "Flag": True}), encoding="utf-8")
    (d / "list.json").write_text(json.dumps([{"word": "Tocasia", "pronunciation": "Toh-kay-zha"}, {"word": "X"}]), encoding="utf-8")
    (d / "notes.txt").write_text("# comment\nUrza = Urz-uh   # trailing\nMishra\tMish\nbad line\nSpaced Out =  yes  \n=nokey\n",
                                 encoding="utf-8")
    (d / "crlf.csv").write_bytes(b"word,pronunciation\r\nAaa,Bbb\r\n\r\nCcc,\r\n")


def load_cases():
    d = HERE / "pron"
    out = []
    for f in sorted(d.iterdir()):
        for keep in (False, True):
            out.append({"file": f.name, "keepBlank": keep, "table": k.load_pronunciations(f, keep_blank=keep)})
    return out


def csv_write_cases():
    rows = [["word", "pronunciation"], ["a,b", 'q"q'], ["line\nbreak", "cr\rhere"], [" lead", "trail "], ["", ""],
            ["Éowyn", "Ay–oh"], ["only"]]
    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerows(rows)
    single = io.StringIO()
    csv.writer(single, lineterminator="\n").writerow([""])
    return {"rows": rows, "text": buf.getvalue(), "singleEmptyField": single.getvalue()}


def apply_cases():
    table = {"Urza Planeswalker": "Er-zuh Plan-ez-walker", "Urza": "Er-zuh", "Mishra": "Mish-ruh", "St.": "Saint",
             "Rhûn": "Roon", "Ma'at": "Mah-aht", "-dash": "DASH", "\U0001F642": "smile", "Menethil II": "M-II", "a b": "ab"}
    texts = ["Urza Planeswalker met Urza and Mishra.", "urza Urza URZA Urza's Urzas", "St. Anselm and Sst. Anselm",
             "Rhûn, Rhûnic, aRhûn, éRhûn, Rhûné", "Ma'at; Ma'ats; xMa'at", "a -dash and a-dash and -dash-",
             "smile \U0001F642 \U0001F642\U0001F642 x\U0001F642", "Terenas Menethil II here", "a b and a  b", ""]
    cases = []
    for t in texts:
        hits = Counter()
        cases.append({"text": t, "result": k.apply_pronunciations(t, table, hits), "hits": dict(hits)})
    return {"table": table, "cases": cases, "emptyTable": k.apply_pronunciations("Urza", {})}


def roman_cases():
    texts = ["Terenas Menethil II ruled.", "Henry VIII and Menethil II's son", "See Part II and Chapter IV.",
             "I and V and he said II was odd", "world war II and World War III", "the king II", "Rhûn II and Éowyn III",
             "éMenethil II", "Menethil\tXX end", "Louis XIV, Louis XV, Louis XVI. Louis XXI Louis XIX", "Act II Scene III",
             "Term II’s and Menethil’s II", "Ab-Cd II", "Type II diabetes", "X-ray II", "A II", "Zed-II"]
    cases = []
    for t in texts:
        hits = Counter()
        cases.append({"text": t, "result": k.expand_roman_numerals(t, hits), "hits": dict(hits)})
    return cases


def chunk_cases():
    long_p = prose(5200)[0]
    cases = [("", 2500), ("one", 2500), ("a\nb\nc", 2500), ("a\n\nb", 2500), (long_p, 2500), (long_p + "\n" + long_p, 2500),
             ("\n".join(prose(1000, 7)), 2500), ("\n".join(prose(900, 9)), 2000), ("x " * 2000, 2500),
             ("Sentence one. " * 400 + "   ", 500), ("\U0001F642" * 2600, 2500), ("\U0001F642 " * 1200, 2500),
             ("\n".join(prose(1760, 3)), 2500), (("a" * 1750) + "\n" + ("b" * 700), 2500), ("p one.\n" + "q " * 1500 + "\n r", 1000),
             ("Ends with space after stop. " * 60, 300), ("Wide space. Next one. " * 80, 300),
             ("trail. Sep. " * 50, 120)]
    return [{"text": t, "limit": lim, "chunks": k.chunk_text(t, lim)} for t, lim in cases]


def stray_cases():
    texts = ["OceanofPDF.com", "  Hello  \n world  ", "x oceanofpdf y", "oceanofpdf.comx", "xoceanofpdf", "OCEANOFPDF.COM text",
             "— !", "", "   ", "café", " nbsp  and em", "\x1cctl\x1d", "﻿feff", "a_b", "٣"]
    return [{"text": t, "result": k.clean_stray(t)} for t in texts]


def helper_cases():
    paths = ["/tmp/a b/it's.flac", "/tmp/plain.flac", "/tmp/o'neil's/x'y.flac", "/tmp/é/\U0001F642.flac"]
    esc = ["plain", "a=b;c#d\\e\nf", "Book I: The Human Component", "It's", "x\r\ny", ""]
    filters = [(24000, 0.94, 0.90, 4), (22050, 0.94, 0.90, 4.5), (24000, 1.0, 1.0, 0), (44100, 0.9, 0.85, 6), (24000, 0.94, 0.88, 3)]
    return {"concatLine": [{"path": p, "line": k.concat_line(p)} for p in paths],
            "ffEscape": [{"text": s, "result": k.ff_escape(s)} for s in esc],
            "buildFilter": [{"sr": a, "pitch": b, "tempo": c, "bass": d, "result": k.build_filter(a, b, c, d)} for a, b, c, d in filters],
            "fmtSecs": [{"sec": s, "result": k.fmt_secs(s)} for s in (0, 5, 59.9, 60, 3599, 3600, 3725.7, 86400)]}


def merge_cases():
    tmp = Path(tempfile.mkdtemp())
    scenarios = {
        "basic": ("word,count,pronunciation\nNew,3,Noo\nSame,2,Same-ish\nDiff,4,Dif-new\nBlanked,5,Fill\nSkip,2,\n",
                  "word,pronunciation\nSame,Same-ish\nDiff,Dif-old\nBlanked,\nKept,\n"),
        "fresh": ("word,pronunciation\nB,bee\na,ay\n", None),
    }
    out = {}
    for name, (src, gl) in scenarios.items():
        for overwrite in (False, True):
            s, g = tmp / f"{name}_src.csv", tmp / f"{name}_{overwrite}_gl.csv"
            s.write_text(src, encoding="utf-8")
            if gl is not None:
                g.write_text(gl, encoding="utf-8")
            args = [s, g] + (["--overwrite"] if overwrite else [])
            stdout = run_py("update_glossary.py", *args)
            out[f"{name}-{'overwrite' if overwrite else 'keep'}"] = {
                "source": src, "glossary": gl, "overwrite": overwrite, "stdout": stdout, "result": g.read_text(encoding="utf-8")}
    return out


def voice_cases():
    import argparse
    cases = []
    profiles = {"none": None, "deep": {"voice": "am_onyx(4)+am_adam(1)", "fx": True}, "plain": {"voice": "am_onyx", "fx": False},
                "partial": {"tempo": 0.8}}
    flags = [{}, {"fx": True}, {"no_fx": True}, {"voice": "v", "speed": 1.1, "pitch": 0.9, "tempo": 0.8, "bass_db": 6.0}, {"fx": True, "no_fx": True}]
    for pname, prof in profiles.items():
        for fl in flags:
            for fx_default in (True, False):
                a = argparse.Namespace(profile=None, voice=None, speed=None, pitch=None, tempo=None, bass_db=None, fx=False, no_fx=False)
                for kk, v in fl.items():
                    setattr(a, kk, v)
                tmp = Path(tempfile.mkdtemp())
                if prof is not None:
                    (tmp / "p.json").write_text(json.dumps(prof))
                    a.profile = str(tmp / "p.json")
                vp.resolve_voice(a, fx_default=fx_default)
                cases.append({"profile": prof, "flags": fl, "fxDefault": fx_default, "settings": vp.settings_of(a)})
    return cases


def write_dictionary():
    """The English word list pyspellchecker uses (D5), one lowercase word per line."""
    import gzip
    import spellchecker
    src = Path(spellchecker.__file__).parent / "resources" / "en.json.gz"
    words = json.load(gzip.open(src, "rt", encoding="utf-8"))
    out = HERE.parents[1] / "assets" / "dictionary" / "en_words.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(sorted(words)) + "\n", encoding="utf-8")


def main():
    write_dictionary()
    make_epubs()
    write_pron_files()
    pron_sets = {"none": [], "series": ["series.csv"], "series+book": ["series.csv", "book.csv"]}
    for name in ("basic", "images", "ncx_only", "accents"):
        epub_path = HERE / f"{name}.epub"
        sections = k.extract_sections(str(epub_path))
        (HERE / f"sections_{name}.json").write_text(json.dumps(
            [{"index": i, "title": t, "chars": len(x), "text": x} for i, (t, x) in enumerate(sections, 1)],
            ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        for pname, files in pron_sets.items():
            out = run_py("dump_golden.py", epub_path, *[HERE / "pron" / f for f in files])
            (HERE / f"chunks_{name}__{pname.replace('+', '_')}.json").write_text(out, encoding="utf-8")
        for mc in (1, 2):
            with tempfile.TemporaryDirectory() as td:
                run_py("find_unknown_words.py", epub_path, "--min-count", mc, "--out", Path(td) / "w.csv")
                words = (Path(td) / "w.csv").read_text(encoding="utf-8") if (Path(td) / "w.csv").exists() else ""
            (HERE / f"words_{name}_min{mc}.csv").write_text(words, encoding="utf-8")
    units = {"cleanStray": stray_cases(), "applyPronunciations": apply_cases(), "romanNumerals": roman_cases(),
             "chunkText": chunk_cases(), "loadPronunciations": load_cases(), "csvWrite": csv_write_cases(),
             "merge": merge_cases(), "voiceResolve": voice_cases(), **helper_cases(),
             "constants": {"CHUNK_CHARS": k.CHUNK_CHARS, "MIN_CHARS_OTHER": k.MIN_CHARS_OTHER, "DEFAULT_VOICE": vp.DEFAULT_VOICE,
                           "DEFAULT_PITCH": vp.DEFAULT_PITCH, "DEFAULT_TEMPO": vp.DEFAULT_TEMPO, "BASS_GAIN_DB": vp.BASS_GAIN_DB}}
    (HERE / "units.json").write_text(json.dumps(units, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("golden fixtures written to", HERE)


if __name__ == "__main__":
    main()
