// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_core/bardoro_core.dart';

enum ConversionPhase { idle, running, combining, finished, failed, cancelled }

/// Everything the Convert step shows, folded from the stream of [PipelineEvent]s. Immutable, and [apply] is a
/// pure function, so the whole thing is testable without isolates or ffmpeg.
final class ConversionProgress {
  const ConversionProgress({
    this.phase = ConversionPhase.idle,
    this.titles = const [],
    this.totalChapters = 0,
    this.chaptersDone = 0,
    this.currentChapter,
    this.currentTitle = '',
    this.chunk = 0,
    this.chunks = 0,
    this.eta,
    this.elapsed,
    this.log = const [],
    this.error,
    this.hint,
    this.warning,
    this.result,
  });

  static const int maxLogLines = 500;

  final ConversionPhase phase;
  final List<String> titles;
  final int totalChapters;
  final int chaptersDone;
  final int? currentChapter;
  final String currentTitle;
  final int chunk, chunks;
  final Duration? eta, elapsed;
  final List<String> log;
  final String? error, hint, warning;
  final Finished? result;

  bool get isActive =>
      phase == ConversionPhase.running || phase == ConversionPhase.combining;
  bool get isTerminal =>
      phase == ConversionPhase.finished ||
      phase == ConversionPhase.failed ||
      phase == ConversionPhase.cancelled;

  /// 0..1 across the whole book, counting the chunks finished in the current chapter.
  double get fraction {
    if (phase == ConversionPhase.finished) return 1;
    if (totalChapters == 0) return 0;
    final inChapter = chunks == 0 ? 0.0 : (chunk / chunks).clamp(0.0, 1.0);
    return ((chaptersDone + inChapter) / totalChapters).clamp(0.0, 1.0);
  }

  ConversionProgress _copy({
    ConversionPhase? phase,
    List<String>? titles,
    int? totalChapters,
    int? chaptersDone,
    int? currentChapter,
    String? currentTitle,
    int? chunk,
    int? chunks,
    Duration? eta,
    Duration? elapsed,
    List<String>? log,
    String? error,
    String? hint,
    String? warning,
    Finished? result,
  }) => ConversionProgress(
    phase: phase ?? this.phase,
    titles: titles ?? this.titles,
    totalChapters: totalChapters ?? this.totalChapters,
    chaptersDone: chaptersDone ?? this.chaptersDone,
    currentChapter: currentChapter ?? this.currentChapter,
    currentTitle: currentTitle ?? this.currentTitle,
    chunk: chunk ?? this.chunk,
    chunks: chunks ?? this.chunks,
    eta: eta ?? this.eta,
    elapsed: elapsed ?? this.elapsed,
    log: log ?? this.log,
    error: error ?? this.error,
    hint: hint ?? this.hint,
    warning: warning ?? this.warning,
    result: result ?? this.result,
  );

  /// Called when the user presses Convert, before the first event arrives.
  ConversionProgress started() => const ConversionProgress(phase: ConversionPhase.running);

  ConversionProgress apply(PipelineEvent e) => switch (e) {
    LogLine(:final message) => _copy(
      log: [
        ...(log.length >= maxLogLines ? log.sublist(log.length - maxLogLines + 1) : log),
        message,
      ],
    ),
    SectionsFound(:final sections) => _copy(
      titles: [for (final s in sections) s.title],
      totalChapters: sections.length,
    ),
    SettingsMismatch(:final diff) => _copy(
      warning:
          'Voice settings differ from the ones this book was started with '
          '(${diff.keys.join(', ')}). Finished chapters keep the old voice.',
    ),
    ChapterSkipped(:final index, :final title) => _copy(
      chaptersDone: chaptersDone + 1,
      currentChapter: index,
      currentTitle: title,
      chunk: 0,
      chunks: 0,
    ),
    ChunkStarted(:final chapter, :final chunk, :final chunks) => _copy(
      currentChapter: chapter,
      currentTitle: _titleFor(chapter),
      chunk: chunk - 1, // this one is in flight, the ones before it are done
      chunks: chunks,
    ),
    ChunkReused(:final chapter, :final chunk, :final chunks) => _copy(
      currentChapter: chapter,
      currentTitle: _titleFor(chapter),
      chunk: chunk,
      chunks: chunks,
    ),
    ChunkDone(:final chapter, :final chunk) => _copy(currentChapter: chapter, chunk: chunk),
    ChapterDone(:final index, :final title, :final elapsed, :final eta) => _copy(
      chaptersDone: chaptersDone + 1,
      currentChapter: index,
      currentTitle: title,
      chunk: 0,
      chunks: 0,
      elapsed: elapsed,
      eta: eta,
    ),
    Combining() => _copy(phase: ConversionPhase.combining, chunk: 0, chunks: 0),
    Finished() => _copy(phase: ConversionPhase.finished, result: e, eta: Duration.zero),
    Cancelled() => _copy(phase: ConversionPhase.cancelled),
    Failed(:final message, :final hint) => _copy(
      phase: ConversionPhase.failed,
      error: message,
      hint: hint,
    ),
  };

  String _titleFor(int chapter) =>
      chapter >= 1 && chapter <= titles.length ? titles[chapter - 1] : currentTitle;
}
