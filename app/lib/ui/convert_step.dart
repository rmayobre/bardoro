// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_services/bardoro_services.dart';
import 'package:flutter/material.dart';

import '../platform/open_folder.dart';
import '../state/book_controller.dart';
import 'snapshot_builder.dart';

/// Start, watch and cancel the conversion. Progress comes from the worker isolate through a [Snapshot].
class ConvertStep extends StatefulWidget {
  const ConvertStep({super.key, required this.book});

  final BookController book;

  @override
  State<ConvertStep> createState() => _ConvertStepState();
}

class _ConvertStepState extends State<ConvertStep> {
  String? _startError;
  final _scroll = ScrollController();

  Future<void> _start() async {
    final error = await widget.book.startConversion();
    if (mounted) setState(() => _startError = error);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotBuilder(
    snapshot: widget.book.progress,
    builder: (context, p) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(book: widget.book, progress: p, onStart: _start, startError: _startError),
          const SizedBox(height: 16),
          if (p.phase != ConversionPhase.idle) ...[
            LinearProgressIndicator(
              value: p.phase == ConversionPhase.combining ? null : p.fraction,
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text(_statusLine(p)),
            const SizedBox(height: 16),
            Expanded(child: _LogView(lines: p.log, controller: _scroll)),
          ] else
            const Spacer(),
        ],
      ),
    ),
  );

  String _statusLine(ConversionProgress p) {
    switch (p.phase) {
      case ConversionPhase.combining:
        return 'Combining chapters into one .m4b…';
      case ConversionPhase.finished:
        final r = p.result!;
        return 'Done: ${r.chapterMarkers} chapters, ${_dur(r.totalAudio)} of audio, '
            '${(r.bytes / 1e6).toStringAsFixed(1)} MB';
      case ConversionPhase.failed:
        return p.error ?? 'Failed';
      case ConversionPhase.cancelled:
        return 'Cancelled. Finished chapters are kept; press Convert to resume.';
      default:
        final chunk = p.chunks > 0 ? ' · chunk ${p.chunk + 1}/${p.chunks}' : '';
        final eta = p.eta == null ? '' : ' · about ${_dur(p.eta!)} left';
        return 'Chapter ${p.chaptersDone}/${p.totalChapters} done'
            '${p.currentTitle.isEmpty ? '' : ' · ${p.currentTitle}'}$chunk$eta';
    }
  }
}

String _dur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '${h}h ${m}m' : (m > 0 ? '${m}m ${s}s' : '${s}s');
}

class _Header extends StatelessWidget {
  const _Header({
    required this.book,
    required this.progress,
    required this.onStart,
    required this.startError,
  });

  final BookController book;
  final ConversionProgress progress;
  final VoidCallback onStart;
  final String? startError;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                p.phase == ConversionPhase.finished ? 'Your audiobook is ready' : 'Convert to audiobook',
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (p.isActive)
              OutlinedButton.icon(
                onPressed: book.cancelConversion,
                icon: const Icon(Icons.stop),
                label: const Text('Cancel'),
              )
            else ...[
              if (p.phase == ConversionPhase.finished)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => openInFileManager(p.result!.path),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Show file'),
                  ),
                ),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  p.phase == ConversionPhase.cancelled || p.phase == ConversionPhase.failed
                      ? 'Resume'
                      : (book.entry.chaptersFinished > 0 ? 'Continue' : 'Convert'),
                ),
              ),
            ],
          ],
        ),
        if (startError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(startError!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (p.warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(p.warning!, style: TextStyle(color: theme.colorScheme.tertiary)),
          ),
        if (p.phase == ConversionPhase.failed && p.hint != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(p.hint!)),
      ],
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.lines, required this.controller});

  final List<String> lines;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) controller.jumpTo(controller.position.maxScrollExtent);
    });
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.all(12),
        itemCount: lines.length,
        itemBuilder: (_, i) => Text(
          lines[i],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
