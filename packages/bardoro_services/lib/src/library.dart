// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:path/path.dart' as p;
import 'package:zero_nads/zero_nads.dart';

/// Where a book is in its life. Derived from files on disk only, so the app and the CLI stay interchangeable.
enum BookStatus {
  /// No `words.csv` yet: run the unknown-word analysis.
  needsWords,

  /// `words.csv` exists, nothing converted.
  ready,

  /// Some `chapter_XX.flac` files exist.
  inProgress,

  /// The `.m4b` exists.
  done,
}

final class BookEntry {
  const BookEntry({
    required this.project,
    required this.status,
    required this.chaptersFinished,
  });

  final BookProject project;
  final BookStatus status;
  final int chaptersFinished;

  String get slug => project.slug;
  String get epubPath => project.epubPath;
  String get title => p.basenameWithoutExtension(project.epubPath);
}

/// The set of books in a workspace: `books/*.epub` joined with whatever exists under `output/<slug>/`.
final class LibraryService {
  const LibraryService(this.workspace);

  final Workspace workspace;

  Task<List<BookEntry>> scan() => Task(() async {
    final dir = Directory(workspace.booksDir);
    if (!await dir.exists()) return const <BookEntry>[];
    final epubs = <File>[
      await for (final e in dir.list())
        if (e is File && e.path.toLowerCase().endsWith('.epub')) e,
    ]..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return [for (final f in epubs) await _entry(f.path)];
  });

  Future<BookEntry> _entry(String epubPath) async {
    final slug = sanitizeSlug(p.basenameWithoutExtension(epubPath));
    final book = workspace.book(slug, epubPath: epubPath);
    var finished = 0;
    final chapters = Directory(book.chaptersDir);
    if (await chapters.exists()) {
      final re = RegExp(r'^chapter_\d+\.flac$');
      finished = await chapters
          .list()
          .where((e) => e is File && re.hasMatch(p.basename(e.path)))
          .length;
    }
    final BookStatus status;
    if (await File(book.m4bPath).exists()) {
      status = BookStatus.done;
    } else if (finished > 0) {
      status = BookStatus.inProgress;
    } else if (await File(book.wordsCsv).exists()) {
      status = BookStatus.ready;
    } else {
      status = BookStatus.needsWords;
    }
    return BookEntry(project: book, status: status, chaptersFinished: finished);
  }

  /// Copies an epub into `books/` (a file already there is reused) and returns its entry. Fails with a
  /// [Result.failure] when the source is missing or not an `.epub`.
  Task<Result<BookEntry>> import(String sourcePath) => Task(
    () => Result.runAsync<BookEntry>(() async {
      if (!sourcePath.toLowerCase().endsWith('.epub')) {
        throw ArgumentError('"${p.basename(sourcePath)}" is not an .epub file');
      }
      final src = File(sourcePath);
      if (!await src.exists()) {
        throw FileSystemException('Epub not found', sourcePath);
      }
      await Directory(workspace.booksDir).create(recursive: true);
      final dest = p.join(workspace.booksDir, p.basename(sourcePath));
      if (!p.equals(src.path, dest) && !await File(dest).exists()) {
        await src.copy(dest);
      }
      return _entry(dest);
    }),
  );

  /// Writes each `relative path -> content` pair under the workspace if the file is missing. Used to seed the
  /// bundled voice profiles and glossaries without ever overwriting the user's edits.
  static Task<int> seed(Workspace workspace, Map<String, String> files) =>
      Task(() async {
        var written = 0;
        for (final e in files.entries) {
          final f = File(p.join(workspace.root, e.key));
          if (await f.exists()) continue;
          await f.parent.create(recursive: true);
          await f.writeAsString(e.value);
          written++;
        }
        return written;
      });

  Task<List<String>> glossaryNames() => Task(() async {
    final dir = Directory(workspace.glossariesDir);
    if (!await dir.exists()) return const <String>[];
    return [
      await for (final e in dir.list())
        if (e is File && e.path.toLowerCase().endsWith('.csv'))
          p.basename(e.path),
    ]..sort();
  });

  Task<List<VoiceProfile>> voiceProfiles() => Task(() async {
    final r = await Result.runAsync<List<VoiceProfile>>(
      () => VoiceProfileRepository(workspace.voicesDir).list(),
    );
    return r.getOrDefault(const <VoiceProfile>[]);
  });
}
