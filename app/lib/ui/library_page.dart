// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_services/bardoro_services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'book_page.dart';
import 'snapshot_builder.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      dialogTitle: 'Choose an epub',
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final result = await controller.importEpub(path);
    result.onFailure((e) => messenger.showSnackBar(SnackBar(content: Text('$e'))));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Library'),
      actions: [
        IconButton(
          tooltip: 'Rescan books folder',
          icon: const Icon(Icons.refresh),
          onPressed: controller.refresh,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: FilledButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add book'),
          ),
        ),
      ],
    ),
    body: SnapshotBuilder(
      snapshot: controller.library,
      builder: (context, lib) {
        if (lib.error != null) {
          return Center(child: Text('Could not read the library: ${lib.error}'));
        }
        if (lib.books.isEmpty) {
          return lib.loading
              ? const Center(child: CircularProgressIndicator())
              : _Empty(onAdd: () => _add(context));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: 150,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: lib.books.length,
          itemBuilder: (context, i) => _BookCard(
            entry: lib.books[i],
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BookPage(app: controller, entry: lib.books[i]),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.menu_book_outlined, size: 64),
        const SizedBox(height: 12),
        Text('No books yet', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Add an epub to turn it into a chaptered audiobook.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add book'),
        ),
      ],
    ),
  );
}

String statusLabel(BookEntry e) => switch (e.status) {
  BookStatus.needsWords => 'Needs word review',
  BookStatus.ready => 'Ready to convert',
  BookStatus.inProgress => '${e.chaptersFinished} chapters converted',
  BookStatus.done => 'Audiobook ready',
};

class _BookCard extends StatelessWidget {
  const _BookCard({required this.entry, required this.onOpen});

  final BookEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry.status) {
      BookStatus.needsWords => (Icons.spellcheck, scheme.tertiary),
      BookStatus.ready => (Icons.play_circle_outline, scheme.primary),
      BookStatus.inProgress => (Icons.pending_outlined, scheme.secondary),
      BookStatus.done => (Icons.check_circle_outline, Colors.green),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(statusLabel(entry), style: TextStyle(color: color)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
