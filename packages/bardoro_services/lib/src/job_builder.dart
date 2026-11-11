// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:path/path.dart' as p;
import 'package:zero_nads/zero_nads.dart';

import 'conversion.dart';
import 'library.dart';
import 'settings.dart';
import 'words_file.dart';

/// Turns "this book + these choices" into a [ConversionRequest].
///
/// Pronunciations are layered like the CLI's repeated `--pronunciations` option: the chosen glossaries in the
/// order given, then the book's own `words.csv` last, so the book wins. Blank respellings are dropped.
final class JobBuilder {
  const JobBuilder(this.settings);

  final AppSettings settings;

  Workspace get workspace => Workspace(settings.workspaceDir);

  Task<Result<ConversionRequest>> build(
    BookEntry book, {
    required VoiceSettings voice,
    String? profileName,
    List<String> glossaries = const [],
    bool romanNumerals = true,
  }) => Task(
    () => Result.runAsync<ConversionRequest>(() async {
      final url = settings.kokoroUrlOption.getOrElse(
        () => throw StateError(
          'No Kokoro server URL. Set it in Settings before converting.',
        ),
      );
      final tables = <PronunciationTable>[];
      for (final name in glossaries) {
        tables.add(
          await const PronunciationFileIO().load(
            File(p.join(workspace.glossariesDir, name)),
          ),
        );
      }
      final words = File(book.project.wordsCsv);
      if (await words.exists()) {
        tables.add(WordsFile.toTable(WordsFile.parse(await words.readAsString())));
      }
      return ConversionRequest(
        job: PipelineJob(
          epubPath: book.epubPath,
          workDir: book.project.chaptersDir,
          outPath: book.project.m4bPath,
          pronunciations: layered(tables),
          voice: voice,
          romanNumerals: romanNumerals,
          profileName: profileName?.isEmpty ?? true ? null : profileName,
        ),
        kokoroUrl: url,
        ffmpeg: settings.ffmpegPath,
        ffprobe: settings.ffprobePath,
      );
    }),
  );
}
