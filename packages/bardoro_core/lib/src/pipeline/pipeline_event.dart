// SPDX-License-Identifier: GPL-3.0-or-later
import '../epub/section_extractor.dart';

sealed class PipelineEvent {
  const PipelineEvent();
}

/// A timestamped line, exactly as written to convert.log (`YYYY-MM-DD HH:MM:SS message` there, `HH:MM:SS message`
/// on the console).
class LogLine extends PipelineEvent {
  const LogLine(this.message);

  final String message;
}

class SectionsFound extends PipelineEvent {
  const SectionsFound(this.sections);

  final List<Section> sections;
}

/// Voice settings differ from the ones the book was started with. Finished chapters keep the old voice.
class SettingsMismatch extends PipelineEvent {
  const SettingsMismatch(this.diff);

  /// key -> (recorded, current)
  final Map<String, (Object?, Object?)> diff;
}

class ChapterSkipped extends PipelineEvent {
  const ChapterSkipped(this.index, this.title);

  final int index;
  final String title;
}

class ChunkStarted extends PipelineEvent {
  const ChunkStarted(this.chapter, this.chunk, this.chunks);

  final int chapter, chunk, chunks;
}

/// A chunk file from an interrupted run was reused.
class ChunkReused extends PipelineEvent {
  const ChunkReused(this.chapter, this.chunk, this.chunks);

  final int chapter, chunk, chunks;
}

class ChunkDone extends PipelineEvent {
  const ChunkDone(this.chapter, this.chunk, this.chars, this.took);

  final int chapter, chunk, chars;
  final Duration took;
}

class ChapterDone extends PipelineEvent {
  const ChapterDone(this.index, this.title, this.audio, this.elapsed, this.eta);

  final int index;
  final String title;
  final Duration audio, elapsed, eta;
}

class Combining extends PipelineEvent {
  const Combining();
}

class Finished extends PipelineEvent {
  const Finished(this.path, this.bytes, this.totalAudio, this.chapterMarkers);

  final String path;
  final int bytes, chapterMarkers;
  final Duration totalAudio;
}

class Cancelled extends PipelineEvent {
  const Cancelled();
}

class Failed extends PipelineEvent {
  const Failed(this.message, {this.hint});

  final String message;
  final String? hint;
}
