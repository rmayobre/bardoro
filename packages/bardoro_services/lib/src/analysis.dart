// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_core/bardoro_core.dart';
import 'package:volley/volley.dart';
import 'package:zero_nads/zero_nads.dart';

/// What the wizard shows after opening an epub: the sections that will be read and the words worth a respelling.
/// Only plain data, so it crosses the isolate boundary.
final class BookAnalysis {
  const BookAnalysis({required this.sections, required this.words});

  final List<Section> sections;
  final List<WordCount> words;

  int get totalChars => sections.fold(0, (n, s) => n + cpLen(s.text));
}

/// Parses an epub off the UI isolate: a volley `coroutine` runs the (CPU heavy) section extraction and
/// unknown-word search in its own short-lived isolate, so a 500-page book never stalls the interface.
///
/// Call `Bootstrapper.initialize()` once at startup before using [analyze].
final class BookAnalyzer {
  const BookAnalyzer({required this.dictionaryPath});

  /// Plain text word list, one word per line (`en_words.txt`).
  final String dictionaryPath;

  /// Lazy: nothing starts until the [Task] is run. Failures (missing file, not an epub) come back as a
  /// [Result.failure] rather than a thrown error.
  Task<Result<BookAnalysis>> analyze(
    String epubPath, {
    int minCount = 2,
    Set<String> known = const {},
  }) {
    // Copy into locals: the closure below is sent to another isolate and must not capture `this` or the UI.
    final dictionary = dictionaryPath;
    final knownWords = Set<String>.of(known);
    return Task(
      () => Result.runAsync<BookAnalysis>(
        () => coroutine<BookAnalysis>(
          () => analyzeEpub(
            epubPath,
            dictionaryPath: dictionary,
            minCount: minCount,
            known: knownWords,
          ),
        ).result,
      ),
    );
  }
}

/// The work itself, usable directly (and in tests) without an isolate.
Future<BookAnalysis> analyzeEpub(
  String epubPath, {
  required String dictionaryPath,
  int minCount = 2,
  Set<String> known = const {},
}) async {
  final book = await EpubReader.open(epubPath);
  final sections = const SectionExtractor().extract(book);
  final words = UnknownWordFinder(
    await WordList.fromFile(dictionaryPath),
  ).find(book, minCount: minCount, known: known);
  return BookAnalysis(sections: sections, words: words);
}
