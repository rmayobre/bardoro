// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:volley/volley.dart';

import 'app.dart';
import 'state/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // volley's shared host isolate: needed once before coroutine()/actor() are used.
    await Bootstrapper.initialize();
    final controller = await AppBootstrap.create();
    runApp(BardoroApp(controller: controller));
  } catch (e, st) {
    // Show the problem instead of leaving an empty window.
    runApp(StartupErrorApp(error: e, stackTrace: st));
  }
}
