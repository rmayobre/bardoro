// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bardoro/app.dart';
import 'package:bardoro/state/app_controller.dart';
import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zero_nads/zero_nads.dart';

AppController _controller(Directory tmp, {Analyzer? analyze, String url = ''}) =>
    AppController(
      store: SettingsStore(p.join(tmp.path, 'cfg', 'settings.json'), defaultWorkspace: p.join(tmp.path, 'ws')),
      settings: AppSettings(workspaceDir: p.join(tmp.path, 'ws'), kokoroUrl: url),
      analyzer: const BookAnalyzer(dictionaryPath: 'unused'),
      analyze: analyze,
    );

/// A throwaway file named like an epub; the injected analyzer never opens it.
File _fakeEpub(Directory tmp, String name) {
  final f = File(p.join(tmp.path, 'ws', 'books', name))..createSync(recursive: true);
  f.writeAsBytes(ZipEncoder().encode(Archive()));
  return f;
}

Task<Result<BookAnalysis>> _fakeAnalysis(String _) => Task(
  () async => Result.success(
    const BookAnalysis(
      sections: [
        Section(index: 1, title: 'Prologue', text: 'Once upon a time.'),
        Section(index: 2, title: 'Chapter 1', text: 'Urza smiled.'),
      ],
      words: [WordCount('Urza', 7), WordCount('Mishra', 3)],
    ),
  ),
);

/// Real file IO finishes on the real event loop, so alternate real waits with frame pumps until [done] holds.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: 'condition never became true');
}

void main() {
  late Directory tmp;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => tmp = Directory.systemTemp.createTempSync('bardoro_ui'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the word list and seed assets ship inside the app bundle', () async {
    final dict = await rootBundle.load('packages/bardoro_core/assets/dictionary/en_words.txt');
    expect(dict.lengthInBytes, greaterThan(1000000));
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets().where((a) => a.startsWith('assets/seed/')),
      containsAll(['assets/seed/voices/deep-narrator.json', 'assets/seed/glossaries/warcraft.csv']),
    );
  });

  testWidgets('empty library invites you to add a book', (tester) async {
    await tester.runAsync(() async {
      final c = _controller(tmp);
      await tester.pumpWidget(BardoroApp(controller: c));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('No books yet'), findsOneWidget);
    expect(find.text('Add book'), findsWidgets);
  });

  testWidgets('settings are saved and reflected in the controller', (tester) async {
    final c = _controller(tmp);
    await tester.pumpWidget(BardoroApp(controller: c));
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Server URL'), 'https://k.example');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(c.settings.value.kokoroUrl, 'https://k.example');
    expect(find.text('Saved'), findsOneWidget);
    expect(File(p.join(tmp.path, 'cfg', 'settings.json')).readAsStringSync(), contains('https://k.example'));
  });

  testWidgets('a book walks through the wizard and edits words.csv', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _fakeEpub(tmp, 'Test Book.epub');
    final c = _controller(tmp, analyze: _fakeAnalysis);
    await tester.pumpWidget(BardoroApp(controller: c));
    await tester.runAsync(() async {
      await c.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Test Book'), findsOneWidget);
    expect(find.text('Needs word review'), findsOneWidget);

    await tester.tap(find.text('Test Book'));
    await tester.pump(); // push the route
    await _until(tester, () => find.text('Prologue').evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    // Step 1: sections
    expect(find.text('2 sections will be read, 29 characters.'), findsOneWidget);
    expect(find.text('Prologue'), findsOneWidget);
    // words.csv is written as soon as the analysis finishes
    final words = File(p.join(tmp.path, 'ws', 'output', 'Test_Book', 'words.csv'));
    await _until(tester, words.existsSync);

    // Step 2: words
    await tester.tap(find.text('Next: Words'));
    await tester.pumpAndSettle();
    expect(find.text('Urza'), findsOneWidget);
    await _until(tester, () => find.text('Saved').evaluate().isNotEmpty); // the initial words.csv write
    await tester.enterText(find.byType(TextField).at(1), 'Er-zuh');
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await _until(tester, () => find.text('Saved').evaluate().isNotEmpty);
    expect(words.readAsStringSync(), 'word,count,pronunciation\nUrza,7,Er-zuh\nMishra,3,\n');

    // Step 3: voice, with the seeded profiles unavailable here the built-in default shows
    await tester.tap(find.text('Next: Voice'));
    await tester.pumpAndSettle();
    expect(find.text('Built-in default'), findsOneWidget);
    expect(find.widgetWithText(TextField, defaultVoice), findsOneWidget);

    // Step 4: converting without a server URL explains what to do instead of starting
    await tester.tap(find.text('Next: Convert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert').last);
    await _until(tester, () => find.textContaining('No Kokoro server URL').evaluate().isNotEmpty);
  });
}
