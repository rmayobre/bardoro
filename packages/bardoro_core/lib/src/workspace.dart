// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:path/path.dart' as p;

/// Folder layout shared with the Python CLI (FLUTTER_CONVERSION.md §4.2), so
/// either tool can work on the same books.
class Workspace {
  const Workspace(this.root);

  final String root;

  String get booksDir => p.join(root, 'books');
  String get voicesDir => p.join(root, 'voices');
  String get glossariesDir => p.join(root, 'glossaries');
  String get outputDir => p.join(root, 'output');

  BookProject book(String slug, {required String epubPath}) =>
      BookProject(slug: slug, epubPath: epubPath, workspace: this);
}

/// `output/<slug>/...` for one book.
class BookProject {
  const BookProject({
    required this.slug,
    required this.epubPath,
    required this.workspace,
  });

  final String slug;
  final String epubPath;
  final Workspace workspace;

  String get dir => p.join(workspace.outputDir, slug);
  String get wordsCsv => p.join(dir, 'words.csv');
  String get legacyNamesCsv => p.join(dir, 'names.csv');
  String get chaptersDir => p.join(dir, 'chapters');
  String get m4bPath => p.join(dir, '$slug.m4b');
  String get voiceSettingsJson => p.join(chaptersDir, 'voice_settings.json');
  String get logFile => p.join(chaptersDir, 'convert.log');

  String chapterFlac(int index) =>
      p.join(chaptersDir, 'chapter_${_two(index)}.flac');
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Work-folder names have no spaces or apostrophes: `[^\w.-]+` -> `_`, trimmed
/// of `_` (Python: `re.sub(r"[^\w.-]+", "_", stem).strip("_")`).
String sanitizeSlug(String stem) => stem
    .replaceAll(RegExp(r'[^\p{L}\p{N}_.-]+', unicode: true), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');
