// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:zero_nads/zero_nads.dart';

import 'app_controller.dart';

enum WizardStep { sections, words, voice, convert }

/// One book's wizard. Immutable; [BookController] swaps in new instances.
final class BookState {
  const BookState({
    this.step = WizardStep.sections,
    this.loading = true,
    this.error,
    this.analysis = const Option<BookAnalysis>(null),
    this.profiles = const [],
    this.glossaryNames = const [],
    this.profile = '',
    this.voice = const VoiceSettings(),
    this.glossaries = const [],
    this.romanNumerals = true,
    this.wordsDirty = false,
  });

  final WizardStep step;
  final bool loading;
  final String? error;
  final Option<BookAnalysis> analysis;
  final List<VoiceProfile> profiles;
  final List<String> glossaryNames;
  final String profile;
  final VoiceSettings voice;
  final List<String> glossaries;
  final bool romanNumerals;
  final bool wordsDirty;

  BookState copyWith({
    WizardStep? step,
    bool? loading,
    Option<String>? error,
    Option<BookAnalysis>? analysis,
    List<VoiceProfile>? profiles,
    List<String>? glossaryNames,
    String? profile,
    VoiceSettings? voice,
    List<String>? glossaries,
    bool? romanNumerals,
    bool? wordsDirty,
  }) => BookState(
    step: step ?? this.step,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error.getOrNull(),
    analysis: analysis ?? this.analysis,
    profiles: profiles ?? this.profiles,
    glossaryNames: glossaryNames ?? this.glossaryNames,
    profile: profile ?? this.profile,
    voice: voice ?? this.voice,
    glossaries: glossaries ?? this.glossaries,
    romanNumerals: romanNumerals ?? this.romanNumerals,
    wordsDirty: wordsDirty ?? this.wordsDirty,
  );
}

/// State and actions for the Sections → Words → Voice → Convert wizard of a single book.
final class BookController {
  BookController(this.app, this.entry)
    : state = Snapshot(const BookState()),
      _session = app.sessionFactory();

  final AppController app;
  final BookEntry entry;
  final Snapshot<BookState> state;
  final ConversionSession _session;

  /// Rows of `words.csv`, edited in place. Kept outside [state] so typing a respelling doesn't rebuild the page;
  /// [BookState.wordsDirty] says when there is something to save.
  List<WordRow> words = [];

  /// Bumped on every edit, so a save that was already in flight doesn't mark newer edits as saved.
  int _wordsRevision = 0;

  /// Live conversion progress (a zero_nads Snapshot fed by the worker isolate).
  Snapshot<ConversionProgress> get progress => _session.progress;

  bool get isConverting => _session.isRunning;

  BookProject get project => entry.project;

  Future<void> load() async {
    state.value = state.value.copyWith(loading: true, error: const Option(null));
    final settings = app.settings.value;
    final lib = app.libraryService;
    final profiles = await lib.voiceProfiles().run();
    final glossaryNames = await lib.glossaryNames().run();

    final analysis = await app.analyze(entry.epubPath).run();
    final existing = await WordsFile.load(project.wordsCsv).run();
    final VoiceProfile? preferred = profiles.where((p) => p.name == settings.profile).firstOrNull;

    analysis
        .onSuccess((a) {
        // A words.csv on disk (from the CLI or an earlier session) always wins over a fresh analysis.
        words = existing.getOrNull() ?? WordsFile.fromAnalysis(a.words);
        state.value = state.value.copyWith(
          loading: false,
          analysis: Option(a),
          profiles: profiles,
          glossaryNames: glossaryNames,
          profile: preferred?.name ?? '',
          voice: resolveVoice(profile: preferred),
          glossaries: [
            for (final g in settings.glossaries)
              if (glossaryNames.contains(g)) g,
          ],
          wordsDirty: existing.isFailure,
        );
        })
        .onFailure((e) {
          state.value = state.value.copyWith(
            loading: false,
            error: Option('Could not read this epub: $e'),
          );
        });
    // Phase 1 of the CLI workflow: write words.csv straight away so either tool can continue.
    if (existing.isFailure && analysis.isSuccess) await saveWords();
  }

  void goTo(WizardStep step) => state.value = state.value.copyWith(step: step);

  void setPronunciation(int index, String value) {
    final row = words[index];
    if (row.pronunciation == value) return;
    words[index] = row.withPronunciation(value);
    _wordsRevision++;
    if (!state.value.wordsDirty) {
      state.value = state.value.copyWith(wordsDirty: true);
    }
  }

  Future<void> saveWords() async {
    final revision = _wordsRevision;
    await WordsFile.save(project.wordsCsv, List.of(words)).run();
    if (revision == _wordsRevision) {
      state.value = state.value.copyWith(wordsDirty: false);
    }
    await app.refresh();
  }

  void selectProfile(String name) {
    final profile = state.value.profiles.where((p) => p.name == name).firstOrNull;
    state.value = state.value.copyWith(
      profile: profile?.name ?? '',
      voice: resolveVoice(profile: profile),
    );
  }

  void setVoice(VoiceSettings voice) =>
      state.value = state.value.copyWith(voice: voice);

  void toggleGlossary(String name, bool on) {
    final next = [...state.value.glossaries]..remove(name);
    if (on) next.add(name); // order matters: later glossaries win
    state.value = state.value.copyWith(glossaries: next);
  }

  void setRomanNumerals(bool on) =>
      state.value = state.value.copyWith(romanNumerals: on);

  /// Saves words and choices, builds the job and starts the worker. Returns an error message to show, or null.
  Future<String?> startConversion() async {
    if (state.value.wordsDirty) await saveWords();
    final s = state.value;
    await app.saveSettings(
      app.settings.value.copyWith(profile: s.profile, glossaries: s.glossaries),
    );
    final request = await JobBuilder(app.settings.value)
        .build(
          entry,
          voice: s.voice,
          profileName: s.profile,
          glossaries: s.glossaries,
          romanNumerals: s.romanNumerals,
        )
        .run();
    final built = request.getOrNull();
    if (built == null) {
      var message = 'Could not prepare the conversion.';
      request.onFailure((e) => message = e is StateError ? e.message : '$e');
      return message;
    }
    unawaited(
      _session.start(built).then((_) => _session.finished).then((_) => app.refresh()),
    );
    return null;
  }

  Future<void> cancelConversion() => _session.cancel();

  Future<void> dispose() => _session.dispose();
}
