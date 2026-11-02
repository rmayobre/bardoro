// SPDX-License-Identifier: GPL-3.0-or-later
// Local parity check against the Python tools on a real epub (nothing is written to the repo).
//
//   dart run tool/parity_check.dart --python ../../.venv/bin/python ../../books/Some.epub [glossary.csv ...]
//
// Compares section titles, char counts, chunks (tools/dump_golden.py) and words.csv (find_unknown_words.py).
import 'dart:convert';
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';

Future<void> main(List<String> args) async {
  var python = 'python3';
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--python') {
      python = args[++i];
    } else {
      rest.add(args[i]);
    }
  }
  if (rest.isEmpty) {
    stderr.writeln(
      'usage: parity_check.dart [--python PY] book.epub [glossary ...]',
    );
    exit(2);
  }
  final epubPath = File(rest.first).absolute.path;
  final pron = [for (final g in rest.skip(1)) File(g).absolute.path];
  final tools = Directory('../../tools').absolute.path;
  final py = File(python).absolute.path;

  final r = await Process.run(
    py,
    ['dump_golden.py', epubPath, ...pron],
    workingDirectory: tools,
    stdoutEncoding: utf8,
  );
  if (r.exitCode != 0) {
    stderr.writeln(r.stderr);
    exit(1);
  }
  final golden = jsonDecode(r.stdout as String) as List;

  final book = await EpubReader.open(epubPath);
  final sections = const SectionExtractor().extract(book);
  final table = layered([
    for (final g in pron) await const PronunciationFileIO().load(File(g)),
  ]);
  final applier = PronunciationApplier(table);

  var bad = 0;
  void fail(String m) {
    bad++;
    stdout.writeln('  MISMATCH $m');
  }

  if (sections.length != golden.length) {
    fail('section count ${sections.length} vs ${golden.length}');
  }
  for (var i = 0; i < sections.length && i < golden.length; i++) {
    final g = golden[i] as Map<String, dynamic>;
    final s = sections[i];
    if (s.title != g['title']) {
      fail('title #${i + 1}: "${s.title}" vs "${g['title']}"');
    }
    if (cpLen(s.text) != g['chars']) {
      fail('chars #${i + 1}: ${cpLen(s.text)} vs ${g['chars']}');
    }
    final chunks = chunkText(expandRomanNumerals(applier.apply(s.text)));
    final want = List<String>.from(g['chunks'] as List);
    if (chunks.length != want.length ||
        [
          for (var k = 0; k < chunks.length; k++) chunks[k] == want[k],
        ].contains(false)) {
      fail('chunks #${i + 1} (${s.title}): ${chunks.length} vs ${want.length}');
    }
  }

  final tmp = await Directory.systemTemp.createTemp('bardoro_parity');
  final wordsOut = '${tmp.path}/w.csv';
  final w = await Process.run(py, [
    'find_unknown_words.py',
    epubPath,
    '--out',
    wordsOut,
  ], workingDirectory: tools);
  if (w.exitCode != 0) {
    stderr.writeln(w.stderr);
    exit(1);
  }
  final dict = await WordList.fromFile('assets/dictionary/en_words.txt');
  final mine = wordsCsv(UnknownWordFinder(dict).find(book));
  final theirs = File(wordsOut).existsSync()
      ? File(wordsOut).readAsStringSync()
      : '';
  if (mine != theirs) {
    final a = mine.split('\n'), b = theirs.split('\n');
    final n = a.length < b.length ? a.length : b.length;
    var first = -1;
    for (var k = 0; k < n; k++) {
      if (a[k] != b[k]) {
        first = k;
        break;
      }
    }
    fail(
      'words.csv differs (${a.length} vs ${b.length} lines; first difference at line ${first + 1}: '
      '"${first >= 0 ? a[first] : ''}" vs "${first >= 0 ? b[first] : ''}")',
    );
  }
  await tmp.delete(recursive: true);
  stdout.writeln(
    '${rest.first.split('/').last}: ${sections.length} sections, ${bad == 0 ? 'PARITY OK' : '$bad mismatch(es)'}',
  );
  exit(bad == 0 ? 0 : 1);
}
