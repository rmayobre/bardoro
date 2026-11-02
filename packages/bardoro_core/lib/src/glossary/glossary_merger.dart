// SPDX-License-Identifier: GPL-3.0-or-later
import 'pronunciation_files.dart';

class MergeResult {
  const MergeResult(this.added, this.replaced, this.conflicts, this.result);

  final List<String> added;

  /// "word: 'old' -> 'new'"
  final List<String> replaced;

  /// "word: keeping 'x', book has 'y'"
  final List<String> conflicts;
  final PronunciationTable result;
}

/// Port of the loop in `update_glossary.py` (Appendix D). [source] holds filled-in entries only;
/// [glossary] must be loaded with blank rows kept: a blank row there is an existing decision.
MergeResult mergeGlossary(
  PronunciationTable source,
  PronunciationTable glossary, {
  bool overwrite = false,
}) {
  final result = Map.of(glossary);
  final added = <String>[], replaced = <String>[], conflicts = <String>[];
  source.forEach((word, spoken) {
    if (!result.containsKey(word)) {
      result[word] = spoken;
      added.add(word);
    } else if (result[word] != spoken) {
      if (overwrite) {
        replaced.add('$word: ${pyRepr(result[word]!)} -> ${pyRepr(spoken)}');
        result[word] = spoken;
      } else {
        final kept = result[word]!.isEmpty
            ? "Kokoro's own pronunciation"
            : result[word]!;
        conflicts.add(
          '$word: keeping ${pyRepr(kept)}, book has ${pyRepr(spoken)}',
        );
      }
    }
  });
  return MergeResult(added, replaced, conflicts, result);
}

/// Python `repr()` of a str (enough for messages).
String pyRepr(String s) {
  final q = s.contains("'") && !s.contains('"') ? '"' : "'";
  final body = s
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll(q == "'" ? "'" : '"', '\\$q');
  return '$q$body$q';
}
