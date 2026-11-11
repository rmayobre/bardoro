// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zero_nads/zero_nads.dart';

/// User-level settings. Immutable; use [copyWith].
final class AppSettings {
  const AppSettings({
    required this.workspaceDir,
    this.kokoroUrl = '',
    this.ffmpegPath = 'ffmpeg',
    this.ffprobePath = 'ffprobe',
    this.profile = '',
    this.glossaries = const [],
  });

  /// Folder holding `books/`, `voices/`, `glossaries/` and `output/` (shared with the Python CLI).
  final String workspaceDir;

  /// Kokoro-FastAPI base URL. Never hardcoded; blank until the user sets it.
  final String kokoroUrl;
  final String ffmpegPath;
  final String ffprobePath;

  /// Last used voice profile name, blank for the built-in defaults.
  final String profile;

  /// Last used glossary file names (inside `glossaries/`).
  final List<String> glossaries;

  /// `Some(url)` once a server URL has been entered.
  Option<String> get kokoroUrlOption =>
      Option(kokoroUrl.trim().isEmpty ? null : kokoroUrl.trim());

  AppSettings copyWith({
    String? workspaceDir,
    String? kokoroUrl,
    String? ffmpegPath,
    String? ffprobePath,
    String? profile,
    List<String>? glossaries,
  }) => AppSettings(
    workspaceDir: workspaceDir ?? this.workspaceDir,
    kokoroUrl: kokoroUrl ?? this.kokoroUrl,
    ffmpegPath: ffmpegPath ?? this.ffmpegPath,
    ffprobePath: ffprobePath ?? this.ffprobePath,
    profile: profile ?? this.profile,
    glossaries: glossaries ?? this.glossaries,
  );

  Map<String, Object?> toJson() => {
    'workspace_dir': workspaceDir,
    'kokoro_url': kokoroUrl,
    'ffmpeg_path': ffmpegPath,
    'ffprobe_path': ffprobePath,
    'profile': profile,
    'glossaries': glossaries,
  };

  factory AppSettings.fromJson(
    Map<String, Object?> json, {
    required String fallbackWorkspace,
  }) {
    String text(String key, String fallback) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v : fallback;
    }

    return AppSettings(
      workspaceDir: text('workspace_dir', fallbackWorkspace),
      kokoroUrl: json['kokoro_url'] is String
          ? json['kokoro_url'] as String
          : '',
      ffmpegPath: text('ffmpeg_path', 'ffmpeg'),
      ffprobePath: text('ffprobe_path', 'ffprobe'),
      profile: json['profile'] is String ? json['profile'] as String : '',
      glossaries: [
        if (json['glossaries'] is List)
          for (final g in json['glossaries'] as List)
            if (g is String) g,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Reads and writes [AppSettings] as JSON. Every operation is a lazy [Task]; nothing touches the disk until `.run()`.
final class SettingsStore {
  const SettingsStore(this.file, {required this.defaultWorkspace});

  final String file;

  /// Used when no file exists yet or it has no workspace.
  final String defaultWorkspace;

  /// A missing or unreadable file yields defaults rather than an error, so the app always starts.
  Task<AppSettings> load() => Task(() async {
    final defaults = AppSettings(workspaceDir: defaultWorkspace);
    final result = await Result.runAsync<AppSettings>(() async {
      final f = File(file);
      if (!await f.exists()) return defaults;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map<String, Object?>) return defaults;
      return AppSettings.fromJson(decoded, fallbackWorkspace: defaultWorkspace);
    });
    return result.getOrDefault(defaults);
  });

  Task<AppSettings> save(AppSettings settings) => Task(() async {
    final f = File(file);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(settings.toJson())}\n',
      flush: true,
    );
    await tmp.rename(f.path);
    return settings;
  });

  /// `<dir>/settings.json`
  static String defaultFileIn(String dir) => p.join(dir, 'settings.json');
}
