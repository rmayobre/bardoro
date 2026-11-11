// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../state/book_controller.dart';
import 'convert_step.dart';
import 'snapshot_builder.dart';
import 'voice_step.dart';
import 'words_step.dart';

/// The per-book wizard: Sections → Words → Voice → Convert.
class BookPage extends StatefulWidget {
  const BookPage({super.key, required this.app, required this.entry});

  final AppController app;
  final BookEntry entry;

  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  late final BookController book = widget.app.openBook(widget.entry);

  @override
  void initState() {
    super.initState();
    book.load();
  }

  @override
  void dispose() {
    book.dispose();
    super.dispose();
  }

  static const _labels = {
    WizardStep.sections: ('Sections', Icons.list_alt),
    WizardStep.words: ('Words', Icons.spellcheck),
    WizardStep.voice: ('Voice', Icons.record_voice_over),
    WizardStep.convert: ('Convert', Icons.auto_stories),
  };

  @override
  Widget build(BuildContext context) => SnapshotBuilder(
    snapshot: book.progress,
    builder: (context, progress) => PopScope(
      // Leaving mid-conversion would kill the worker; make the user cancel first.
      canPop: !progress.isActive,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SnapshotBuilder(
              snapshot: book.state,
              builder: (context, s) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<WizardStep>(
                  showSelectedIcon: false,
                  segments: [
                    for (final e in _labels.entries)
                      ButtonSegment(
                        value: e.key,
                        label: Text('${e.key.index + 1}  ${e.value.$1}'),
                        icon: Icon(e.value.$2),
                        enabled: !s.loading && s.error == null && !progress.isActive,
                      ),
                  ],
                  selected: {s.step},
                  onSelectionChanged: (v) => book.goTo(v.single),
                ),
              ),
            ),
          ),
        ),
        body: SnapshotBuilder(
          snapshot: book.state,
          builder: (context, s) {
            if (s.loading) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Reading the epub…'),
                  ],
                ),
              );
            }
            if (s.error != null) return Center(child: Text(s.error!));
            return switch (s.step) {
              WizardStep.sections => _SectionsStep(book: book, state: s),
              WizardStep.words => WordsStep(book: book),
              WizardStep.voice => VoiceStep(book: book),
              WizardStep.convert => ConvertStep(book: book),
            };
          },
        ),
      ),
    ),
  );
}

class _SectionsStep extends StatelessWidget {
  const _SectionsStep({required this.book, required this.state});

  final BookController book;
  final BookState state;

  @override
  Widget build(BuildContext context) {
    final analysis = state.analysis.getOrThrow();
    final already = book.entry.chaptersFinished;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${analysis.sections.length} sections will be read, '
                  '${_thousands(analysis.totalChars)} characters'
                  '${already > 0 ? ' · $already already converted' : ''}.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton(
                onPressed: () => book.goTo(WizardStep.words),
                child: const Text('Next: Words'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: analysis.sections.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = analysis.sections[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${s.index}')),
                title: Text(s.title),
                trailing: Text('${_thousands(cpLen(s.text))} chars'),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _thousands(int n) => n.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
