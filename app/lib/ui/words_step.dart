// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../state/book_controller.dart';
import 'snapshot_builder.dart';

/// Edit `words.csv`: a respelling per unfamiliar word. Blank means "Kokoro already says it right".
class WordsStep extends StatefulWidget {
  const WordsStep({super.key, required this.book});

  final BookController book;

  @override
  State<WordsStep> createState() => _WordsStepState();
}

class _WordsStepState extends State<WordsStep> {
  String _filter = '';
  bool _onlyBlank = false;

  List<int> get _visible {
    final f = _filter.toLowerCase();
    final rows = widget.book.words;
    return [
      for (var i = 0; i < rows.length; i++)
        if ((f.isEmpty || rows[i].word.toLowerCase().contains(f)) &&
            (!_onlyBlank || rows[i].pronunciation.isEmpty))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final visible = _visible;
    final filled = book.words.where((w) => w.pronunciation.isNotEmpty).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filter words',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              FilterChip(
                label: const Text('Only unspelled'),
                selected: _onlyBlank,
                onSelected: (v) => setState(() => _onlyBlank = v),
              ),
              Text('$filled of ${book.words.length} respelled'),
              SnapshotBuilder(
                snapshot: book.state,
                builder: (context, s) => OutlinedButton.icon(
                  onPressed: s.wordsDirty ? book.saveWords : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(s.wordsDirty ? 'Save' : 'Saved'),
                ),
              ),
              FilledButton(
                onPressed: () => book.goTo(WizardStep.voice),
                child: const Text('Next: Voice'),
              ),
            ],
          ),
        ),
        if (book.words.isEmpty)
          const Expanded(
            child: Center(child: Text('No unfamiliar words were found. You can go straight to the voice.')),
          )
        else ...[
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: visible.length,
              itemExtent: 56,
              itemBuilder: (context, n) {
                final index = visible[n];
                final row = book.words[index];
                return _WordTile(
                  key: ValueKey(row.word),
                  word: row.word,
                  count: row.count,
                  initial: row.pronunciation,
                  onChanged: (v) => book.setPronunciation(index, v),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _WordTile extends StatefulWidget {
  const _WordTile({
    super.key,
    required this.word,
    required this.count,
    required this.initial,
    required this.onChanged,
  });

  final String word;
  final int count;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_WordTile> createState() => _WordTileState();
}

class _WordTileState extends State<_WordTile> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 220,
          child: Text(widget.word, style: Theme.of(context).textTheme.titleSmall),
        ),
        SizedBox(
          width: 64,
          child: Text('×${widget.count}', style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: TextField(
            controller: _c,
            onChanged: widget.onChanged,
            decoration: const InputDecoration(
              hintText: 'How it should sound (blank = keep Kokoro\'s)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    ),
  );
}
