// SPDX-License-Identifier: GPL-3.0-or-later

/// Oracle harness: how close are the letter-to-sound rules to a dictionary and to espeak-ng?
///
/// Usage: `dart run tool/oracle.dart [--cmudict cmudict.dict] [--sample 5000] [--out report.md]`
///
/// The word list is a held-out slice of CMUdict (every k-th word of `^[a-z]{3,}$`) or, without
/// `--cmudict`, of our own lexicon's headwords. The rule engine runs alone (no lexicon, no
/// morphology), because that is the situation for invented names. Reference 1 is our bundled
/// lexicon entry (misaki gold/silver); reference 2 is `espeak-ng -v en-us --ipa`, mapped into the
/// Kokoro alphabet. espeak-ng is optional (set `ESPEAK_NG` to its path if it is not on PATH):
/// without it that half is skipped.
library;

import 'dart:io';

import 'package:bardoro_g2p/bardoro_g2p.dart';

Future<void> main(List<String> args) async {
  String? cmudict;
  var sample = 5000;
  String? out;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--cmudict':
        cmudict = args[++i];
      case '--sample':
        sample = int.parse(args[++i]);
      case '--out':
        out = args[++i];
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(64);
    }
  }
  final report = await runOracle(cmudictPath: cmudict, sample: sample);
  if (out != null) {
    File(out).writeAsStringSync(report);
    stdout.writeln('wrote $out');
  } else {
    stdout.write(report);
  }
}

/// The espeak-ng executable: `$ESPEAK_NG` if set, else `espeak-ng` from PATH.
String get espeakBin => Platform.environment['ESPEAK_NG'] ?? 'espeak-ng';

bool espeakAvailable() {
  try {
    return Process.runSync(espeakBin, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// espeak-ng phonemes for [words], one entry per word, or null where the output did not line up.
Future<List<String?>> espeakIpa(List<String> words) async {
  final result = <String?>[];
  const chunk = 1000;
  final dir = Directory.systemTemp.createTempSync('oracle_');
  try {
    for (var i = 0; i < words.length; i += chunk) {
      final part = words.sublist(i, i + chunk > words.length ? words.length : i + chunk);
      final f = File('${dir.path}/w.txt')..writeAsStringSync(part.join('\n'));
      final r = await Process.run(espeakBin, ['-q', '--ipa', '-v', 'en-us', '-f', f.path]);
      final tokens = (r.stdout as String).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length == part.length) {
        result.addAll(tokens);
      } else {
        // a word became zero or several tokens: redo the chunk word by word
        for (final w in part) {
          final one = await Process.run(espeakBin, ['-q', '--ipa', '-v', 'en-us', w]);
          final t = (one.stdout as String).trim();
          result.add(t.isEmpty || t.contains(RegExp(r'\s')) ? null : t);
        }
      }
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
  return result;
}

List<String> sliceWords(String? cmudictPath, Lexicon lexicon, String lexiconPath, int sample) {
  final words = <String>{};
  final re = RegExp(r'^[a-z]{3,}$');
  if (cmudictPath != null) {
    for (final line in File(cmudictPath).readAsLinesSync()) {
      final w = line.split(' ').first;
      if (re.hasMatch(w)) words.add(w);
    }
  } else {
    for (final line in File(lexiconPath).readAsLinesSync()) {
      if (line.startsWith('#')) continue;
      final w = line.split('\t').first;
      if (re.hasMatch(w)) words.add(w);
    }
  }
  final sorted = words.toList()..sort();
  final step = (sorted.length / sample).ceil().clamp(1, sorted.length);
  return [for (var i = 0; i < sorted.length; i += step) sorted[i]];
}

Future<String> runOracle({String? cmudictPath, int sample = 5000, String assets = 'assets'}) async {
  final lexiconPath = '$assets/en_lexicon.txt';
  final lexicon = Lexicon.load(lexiconPath);
  final rulesText = File('$assets/en_us.rules').readAsStringSync();
  final rules = RuleParser().parse(rulesText);
  final engine = RuleEngine(rules, finish: const Finisher().call);
  final mapper = KokoroMapper(
    KokoroVocab.fromConfigJson(File('test/fixtures/kokoro_config.json').readAsStringSync()),
  );

  final words = sliceWords(cmudictPath, lexicon, lexiconPath, sample);
  final haveEspeak = espeakAvailable();
  final espeak = haveEspeak ? await espeakIpa(words) : <String?>[];

  final vsLex = PairStats();
  final vsEsp = PairStats();
  final espVsLex = PairStats(); // how far espeak itself is from the dictionary (the ceiling)
  final ruleStats = <int, RuleStat>{};
  var unresolved = 0;
  var noLexicon = 0;
  var noEspeak = 0;
  var droppedFromEspeak = 0;

  for (var k = 0; k < words.length; k++) {
    final w = words[k];
    final traced = engine.transcribeTraced(w);
    if (traced == null) {
      unresolved++;
      continue;
    }
    final ours = Reductions.flapped(const Finisher().call(traced.phones, w));
    final lexRef = lexicon.lookupPhones(w);
    List<Phone>? espRef;
    if (haveEspeak) {
      final ipa = espeak[k];
      if (ipa == null) {
        noEspeak++;
      } else {
        final m = mapper.fromIpa(ipa);
        droppedFromEspeak += m.dropped.length;
        espRef = parsePhones(m.text);
      }
    }
    var lexErr = false;
    var espErr = false;
    if (lexRef == null) {
      noLexicon++;
    } else {
      lexErr = vsLex.add(w, ours, lexRef) > 0;
    }
    if (espRef != null) {
      espErr = vsEsp.add(w, ours, espRef) > 0;
      if (lexRef != null) espVsLex.add(w, espRef, lexRef);
    }
    for (final line in traced.lines.toSet()) {
      final s = ruleStats.putIfAbsent(line, RuleStat.new);
      s.words++;
      if (lexErr) s.errorWordsVsLexicon++;
      if (espErr) s.errorWordsVsEspeak++;
    }
  }

  String pct(double x) => '${(x * 100).toStringAsFixed(1)}%';
  final b = StringBuffer()
    ..writeln('# bardoro_g2p oracle report')
    ..writeln()
    ..writeln('- Word list: ${cmudictPath != null ? 'CMUdict' : 'lexicon headwords'} slice, ${words.length} words '
        '(`^[a-z]{3,}\$`, every k-th of the sorted list)')
    ..writeln('- Rule engine only (no lexicon, no morphology), flapping on, stress and reduction on')
    ..writeln('- espeak-ng: ${haveEspeak ? Process.runSync(espeakBin, ['--version']).stdout.toString().trim().split('\n').first : 'not installed, espeak comparison skipped'}')
    ..writeln('- Unresolved by the rules: $unresolved; no lexicon entry for reference: $noLexicon'
        '${haveEspeak ? '; no usable espeak output: $noEspeak; symbols espeak produced that the Kokoro vocab lacks: $droppedFromEspeak' : ''}')
    ..writeln()
    ..writeln('| Comparison | Words | PER | Exact words | Stress position (2+ vowels) |')
    ..writeln('|---|---:|---:|---:|---:|')
    ..writeln('| rules vs lexicon | ${vsLex.words} | ${pct(vsLex.per)} | ${pct(vsLex.exactRate)} | ${pct(vsLex.stressAccuracy)} (${vsLex.stressComparable}) |');
  if (haveEspeak) {
    b
      ..writeln('| rules vs espeak-ng | ${vsEsp.words} | ${pct(vsEsp.per)} | ${pct(vsEsp.exactRate)} | ${pct(vsEsp.stressAccuracy)} (${vsEsp.stressComparable}) |')
      ..writeln('| espeak-ng vs lexicon (ceiling) | ${espVsLex.words} | ${pct(espVsLex.per)} | ${pct(espVsLex.exactRate)} | ${pct(espVsLex.stressAccuracy)} (${espVsLex.stressComparable}) |');
  }
  b
    ..writeln()
    ..writeln('PER = phone edit distance / reference phones, stress marks ignored; `ᵊ ɐ` count as `ə` and `ᵻ` as `ɪ`.')
    ..writeln()
    ..writeln('## Rule coverage (rule-file line, section, rule, words using it, error words)')
    ..writeln()
    ..writeln('Error words = words that use the rule and differ from the reference. This is blame, not proof.')
    ..writeln()
    ..writeln('| Line | Section | Rule | Words | Err vs lexicon | Err vs espeak |')
    ..writeln('|---:|---|---|---:|---:|---:|');
  final byBlame = rules.rules.toList()
    ..sort((x, y) => (ruleStats[y.line]?.errorWordsVsLexicon ?? 0).compareTo(ruleStats[x.line]?.errorWordsVsLexicon ?? 0));
  for (final r in byBlame.take(25)) {
    final s = ruleStats[r.line];
    b.writeln('| ${r.line} | ${r.section} | `${r.toString().split(': ').last}` | ${s?.words ?? 0} | ${s?.errorWordsVsLexicon ?? 0} | ${s?.errorWordsVsEspeak ?? 0} |');
  }
  b
    ..writeln()
    ..writeln('(top 25 by words with an error vs lexicon; full per-rule counts are in `engine.ruleHits`)')
    ..writeln()
    ..writeln('## Most common phone errors (ours→reference, ∅ = none)')
    ..writeln();
  for (final (label, st) in [('vs lexicon', vsLex), ('vs espeak-ng', vsEsp)]) {
    if (st.words == 0) continue;
    final top = st.confusions.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    b.writeln('- $label: ${top.take(14).map((e) => '`${e.key}` ${e.value}').join(', ')}');
  }
  b
    ..writeln()
    ..writeln('## Dead rules on this word list')
    ..writeln();
  final dead = [for (final r in rules.rules) if (!ruleStats.containsKey(r.line)) r];
  b.writeln(dead.isEmpty ? 'none' : dead.map((r) => '- line ${r.line}: `${r.toString().split(': ').last}`').join('\n'));
  b
    ..writeln()
    ..writeln('## Worst words vs lexicon (edits, word, ours, lexicon)')
    ..writeln();
  for (final w in vsLex.worst.take(15)) {
    b.writeln('- ${w.$1}: ${w.$2}  ours `${w.$3}`  lexicon `${w.$4}`');
  }
  return b.toString();
}
