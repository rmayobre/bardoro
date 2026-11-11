// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:zero_nads/zero_nads.dart';

import 'book_controller.dart';

/// What the Library screen renders.
final class LibraryState {
  const LibraryState({
    this.books = const [],
    this.loading = false,
    this.error,
  });

  final List<BookEntry> books;
  final bool loading;
  final String? error;
}

/// Opens an epub off the UI isolate. Injected so widget tests don't need isolates.
typedef Analyzer = Task<Result<BookAnalysis>> Function(String epubPath);

/// App-wide state. Every observable is a zero_nads [Snapshot]; the widgets only read these and call methods.
final class AppController {
  AppController({
    required this.store,
    required AppSettings settings,
    required BookAnalyzer analyzer,
    Analyzer? analyze,
    this.sessionFactory = ConversionSession.new,
  }) : settings = Snapshot(settings),
       analyze = analyze ?? ((path) => analyzer.analyze(path));

  final SettingsStore store;
  final Analyzer analyze;
  final ConversionSession Function() sessionFactory;

  final Snapshot<AppSettings> settings;
  final Snapshot<LibraryState> library = Snapshot(const LibraryState());

  Workspace get workspace => Workspace(settings.value.workspaceDir);
  LibraryService get libraryService => LibraryService(workspace);

  /// Whether a Kokoro server URL has been entered.
  bool get hasServerUrl => settings.value.kokoroUrlOption.isSome;

  Future<void> refresh() async {
    library.value = LibraryState(books: library.value.books, loading: true);
    final r = await Result.runAsync<List<BookEntry>>(
      () => libraryService.scan().run(),
    );
    library.value = r.fold(
      onSuccess: (books) => LibraryState(books: books),
      onFailure: (e) => LibraryState(books: library.value.books, error: '$e'),
    );
  }

  /// Copies the epub into the workspace's `books/` folder. The error text is ready to show.
  Future<Result<BookEntry>> importEpub(String path) async {
    final r = await libraryService.import(path).run();
    await refresh();
    return r;
  }

  Future<void> saveSettings(AppSettings next) async {
    settings.value = await store.save(next).run();
    await refresh();
  }

  BookController openBook(BookEntry entry) => BookController(this, entry);
}
