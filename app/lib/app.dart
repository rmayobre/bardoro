// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/shell.dart';

class BardoroApp extends StatelessWidget {
  const BardoroApp({super.key, required this.controller});

  final AppController controller;

  static ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF7A4B2A), // leather-bound brown
      brightness: b,
    ),
    visualDensity: VisualDensity.standard,
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bardoro',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: Shell(controller: controller),
  );
}

/// Shown when the app cannot start (for example the workspace folder is not writable).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bardoro',
    debugShowCheckedModeBanner: false,
    theme: BardoroApp._theme(Brightness.light),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bardoro could not start', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                SelectableText('$error'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
