// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:bardoro_services/bardoro_services.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_controller.dart';

/// Wires the platform (folders, bundled assets) to the platform-free [AppController].
abstract final class AppBootstrap {
  static const _dictionaryAsset =
      'packages/bardoro_core/assets/dictionary/en_words.txt';
  static const _seedPrefix = 'assets/seed/';

  static Future<AppController> create() async {
    final support = await getApplicationSupportDirectory();
    final store = SettingsStore(
      SettingsStore.defaultFileIn(support.path),
      defaultWorkspace: await _defaultWorkspace(),
    );
    final settings = await store.load().run();
    final workspace = Workspace(settings.workspaceDir);

    await LibraryService.seed(workspace, await _seedFiles()).run();
    final dictionary = await _ensureDictionary(support.path);

    return AppController(
      store: store,
      settings: settings,
      analyzer: BookAnalyzer(dictionaryPath: dictionary),
    );
  }

  /// `~/Documents/Bardoro`. Some Linux desktops have no Documents folder configured (no xdg-user-dirs), so fall
  /// back to the home folder rather than failing to start.
  static Future<String> _defaultWorkspace() async {
    try {
      return p.join((await getApplicationDocumentsDirectory()).path, 'Bardoro');
    } on MissingPlatformDirectoryException {
      final env = Platform.environment;
      final home = env['HOME'] ?? env['USERPROFILE'];
      if (home == null || home.isEmpty) rethrow;
      return p.join(home, 'Bardoro');
    }
  }

  /// Bundled starter voices and glossaries, keyed by their path inside the workspace.
  static Future<Map<String, String>> _seedFiles() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return {
      for (final key in manifest.listAssets())
        if (key.startsWith(_seedPrefix))
          key.substring(_seedPrefix.length): await rootBundle.loadString(key),
    };
  }

  /// `rootBundle` can't be read from another isolate, so the word list is written once to a real file the
  /// analysis coroutine can open.
  static Future<String> _ensureDictionary(String supportDir) async {
    final data = await rootBundle.load(_dictionaryAsset);
    final file = File(p.join(supportDir, 'en_words.txt'));
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }
}
