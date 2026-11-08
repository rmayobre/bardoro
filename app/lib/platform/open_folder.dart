// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

/// Shows [path] (a folder, or a file's folder) in the system file manager.
Future<void> openInFileManager(String path) async {
  final dir = FileSystemEntity.isDirectorySync(path) ? path : File(path).parent.path;
  if (Platform.isMacOS) {
    await Process.run('open', [dir]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', [dir]);
  } else {
    await Process.run('xdg-open', [dir]);
  }
}
