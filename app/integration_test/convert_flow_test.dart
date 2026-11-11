// SPDX-License-Identifier: GPL-3.0-or-later
// Runs the real app on a desktop (real volley isolates, the bundled word list, real ffmpeg) against a fake
// Kokoro server:
//
//   xvfb-run -a flutter test integration_test -d linux      (headless Linux)
//   flutter test integration_test -d macos|windows          (needs ffmpeg and ffprobe on PATH)
import 'dart:io';

import 'package:bardoro/app.dart';
import 'package:bardoro/state/bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:volley/volley.dart';

import '../../packages/bardoro_services/test/support/epub_builder.dart';
import '../../packages/bardoro_services/test/support/fake_kokoro.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('epub to .m4b through the real app', (tester) async {
    await Bootstrapper.initialize();
    final server = await FakeKokoro.start();
    addTearDown(server.close);

    final controller = await AppBootstrap.create();
    // Isolate the test from the developer's real workspace and server URL.
    final tmp = await Directory.systemTemp.createTemp('bardoro_it');
    addTearDown(() => tmp.delete(recursive: true));
    await controller.saveSettings(
      controller.settings.value.copyWith(
        workspaceDir: p.join(tmp.path, 'ws'),
        kokoroUrl: server.url,
      ),
    );
    final epub = File(p.join(tmp.path, "The Brothers' War.epub"))
      ..writeAsBytesSync(smokeEpub());
    (await controller.importEpub(epub.path)).getOrThrow();

    await tester.pumpWidget(BardoroApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text("The Brothers' War"), findsOneWidget);

    await tester.tap(find.text("The Brothers' War"));
    await tester.pump();
    // The analysis runs in a volley coroutine: wait for the sections to appear.
    await _until(tester, () => find.text('Prologue').evaluate().isNotEmpty);
    expect(find.textContaining('3 sections will be read'), findsOneWidget);

    await tester.tap(find.text('Next: Words'));
    await tester.pumpAndSettle();
    expect(find.text('Urza'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'Er-zuh');
    await tester.pump();
    await tester.tap(find.text('Next: Voice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: Convert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert').last);

    final m4b = File(p.join(tmp.path, 'ws', 'output', 'The_Brothers_War', 'The_Brothers_War.m4b'));
    await _until(tester, () => find.textContaining('Done: 3 chapters').evaluate().isNotEmpty, seconds: 90);
    expect(m4b.existsSync(), isTrue);
    expect(server.inputs.join('\n'), contains('Er-zuh'));
    expect(server.inputs.join('\n'), isNot(contains('Urza')));
  });
}

Future<void> _until(WidgetTester tester, bool Function() done, {int seconds = 30}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: 'timed out after ${seconds}s');
}
