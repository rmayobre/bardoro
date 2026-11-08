// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'library_page.dart';
import 'settings_page.dart';

/// Navigation rail + the two top-level destinations.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller});

  final AppController controller;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Bardoro',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.library_books_outlined),
                selectedIcon: Icon(Icons.library_books),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
    );
  }
}
