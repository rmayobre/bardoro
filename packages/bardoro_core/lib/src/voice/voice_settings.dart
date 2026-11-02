// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Kokoro-FastAPI weighted blend; use plain "am_onyx" if the server rejects it.
const defaultVoice = 'am_onyx(4)+am_adam(1)';

/// <1 lowers pitch (0.94 is about -1 semitone).
const defaultPitch = 0.94;

/// Final playback speed after the pitch change.
const defaultTempo = 0.90;

/// Low-shelf boost around 150 Hz.
const bassGainDb = 4;

/// Everything that shapes the sound. Mirrors `voice_profiles.BUILTIN`. Numbers are `num` so a value written as
/// `4` in a profile stays `4` in `voice_settings.json`, exactly as in Python.
class VoiceSettings {
  const VoiceSettings({
    this.voice = defaultVoice,
    this.speed = 1.0,
    this.pitch = defaultPitch,
    this.tempo = defaultTempo,
    this.bassDb = bassGainDb,
    this.fx = true,
  });

  final String voice;

  /// Server-side speed; keep near 1.0 (AGENTS.md).
  final num speed;

  /// ffmpeg pitch shift; <1 is deeper.
  final num pitch;

  /// Final speaking speed.
  final num tempo;
  final num bassDb;
  final bool fx;

  /// Same keys and order as `settings_of` in Python.
  Map<String, Object?> toJson() => {
    'voice': voice,
    'speed': speed,
    'pitch': pitch,
    'tempo': tempo,
    'bass_db': bassDb,
    'fx': fx,
  };

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'VoiceSettings(${toJson()})';
}

class VoiceProfileException implements Exception {
  const VoiceProfileException(this.message);

  final String message;

  @override
  String toString() => 'voice profile: $message';
}

/// A profile is a partial VoiceSettings: every key optional (`voices/NAME.json`).
class VoiceProfile {
  const VoiceProfile({
    required this.name,
    this.description,
    this.voice,
    this.speed,
    this.pitch,
    this.tempo,
    this.bassDb,
    this.fx,
  });

  static const _numberKeys = ['speed', 'pitch', 'tempo', 'bass_db'];
  static const keys = {'description', 'voice', ..._numberKeys, 'fx'};

  final String name;
  final String? description;
  final String? voice;
  final num? speed, pitch, tempo, bassDb;
  final bool? fx;

  /// Port of `validate`; [where] names the file in error messages.
  factory VoiceProfile.fromJson(
    Object? data, {
    required String name,
    String? where,
  }) {
    final w = where ?? '$name.json';
    if (data is! Map) {
      throw VoiceProfileException('$w must contain a JSON object');
    }
    final unknown =
        data.keys.where((k) => !keys.contains(k)).map((k) => '$k').toList()
          ..sort();
    if (unknown.isNotEmpty) {
      throw VoiceProfileException(
        '$w has unknown key(s) ${unknown.join(', ')}; allowed: ${(keys.toList()..sort()).join(', ')}',
      );
    }
    for (final k in _numberKeys) {
      if (data.containsKey(k)) {
        final v = data[k];
        if (v is! num || v <= 0) {
          throw VoiceProfileException('$w: $k must be a positive number');
        }
      }
    }
    for (final k in ['voice', 'description']) {
      if (data.containsKey(k) && data[k] is! String) {
        throw VoiceProfileException('$w: $k must be text');
      }
    }
    if (data.containsKey('voice') && (data['voice'] as String).trim().isEmpty) {
      throw VoiceProfileException('$w: voice must not be empty');
    }
    if (data.containsKey('fx') && data['fx'] is! bool) {
      throw VoiceProfileException('$w: fx must be true or false');
    }
    return VoiceProfile(
      name: name,
      description: data['description'] as String?,
      voice: data['voice'] as String?,
      speed: data['speed'] as num?,
      pitch: data['pitch'] as num?,
      tempo: data['tempo'] as num?,
      bassDb: data['bass_db'] as num?,
      fx: data['fx'] as bool?,
    );
  }

  Map<String, Object?> toJson() => {
    if (description != null) 'description': description,
    if (voice != null) 'voice': voice,
    if (speed != null) 'speed': speed,
    if (pitch != null) 'pitch': pitch,
    if (tempo != null) 'tempo': tempo,
    if (bassDb != null) 'bass_db': bassDb,
    if (fx != null) 'fx': fx,
  };
}

/// What was typed explicitly (a flag in the CLI, a field in the UI). Null = not given.
class VoiceOverrides {
  const VoiceOverrides({
    this.voice,
    this.speed,
    this.pitch,
    this.tempo,
    this.bassDb,
    this.fx = false,
    this.noFx = false,
  });

  final String? voice;
  final num? speed, pitch, tempo, bassDb;

  /// `--fx`: force the effect on.
  final bool fx;

  /// `--no-fx`: force the effect off (wins over everything).
  final bool noFx;
}

/// Port of `resolve_voice`: flag, then profile, then built-in default. `fx`:
/// noFx -> false; fx flag -> true; profile has fx -> that; profile given -> true; otherwise [fxDefault]
/// (true for conversion; false for the single-word test unless a profile or --fx).
VoiceSettings resolveVoice({
  VoiceProfile? profile,
  VoiceOverrides overrides = const VoiceOverrides(),
  bool fxDefault = true,
}) {
  const base = VoiceSettings();
  final bool fx;
  if (overrides.noFx) {
    fx = false;
  } else if (overrides.fx) {
    fx = true;
  } else if (profile?.fx != null) {
    fx = profile!.fx!;
  } else if (profile != null) {
    fx = base.fx;
  } else {
    fx = fxDefault;
  }
  return VoiceSettings(
    voice: overrides.voice ?? profile?.voice ?? base.voice,
    speed: overrides.speed ?? profile?.speed ?? base.speed,
    pitch: overrides.pitch ?? profile?.pitch ?? base.pitch,
    tempo: overrides.tempo ?? profile?.tempo ?? base.tempo,
    bassDb: overrides.bassDb ?? profile?.bassDb ?? base.bassDb,
    fx: fx,
  );
}

/// `voices/<name>.json` files. The file name without `.json` is the profile name.
class VoiceProfileRepository {
  const VoiceProfileRepository(this.dir);

  final String dir;

  /// A profile by name (`dir/NAME.json`) or by an explicit path to a `.json` file.
  Future<VoiceProfile> load(String nameOrPath) async {
    final direct = File(nameOrPath);
    final File file;
    if (nameOrPath.toLowerCase().endsWith('.json') && await direct.exists()) {
      file = direct;
    } else {
      file = File(p.join(dir, '$nameOrPath.json'));
      if (!await file.exists()) {
        final names = await _names();
        throw VoiceProfileException(
          'no profile named \'$nameOrPath\' in $dir (available: ${names.isEmpty ? 'none yet' : names.join(', ')})',
        );
      }
    }
    final stem = p.basenameWithoutExtension(file.path);
    final Object? data;
    try {
      data = jsonDecode(await file.readAsString());
    } on FormatException catch (e) {
      throw VoiceProfileException(
        '${file.path} is not valid JSON: ${e.message}',
      );
    }
    return VoiceProfile.fromJson(
      data,
      name: stem,
      where: p.basename(file.path),
    );
  }

  Future<List<String>> _names() async {
    final d = Directory(dir);
    if (!await d.exists()) return [];
    return [
      await for (final f in d.list())
        if (f is File && f.path.endsWith('.json'))
          p.basenameWithoutExtension(f.path),
    ]..sort();
  }

  Future<List<VoiceProfile>> list() async => [
    for (final n in await _names()) await load(n),
  ];

  /// `voice_profiles.py new NAME`: letters, digits, '-' and '_' only; refuses to overwrite unless [force].
  Future<File> create(VoiceProfile profile, {bool force = false}) async {
    if (!RegExp(r'^[\p{L}\p{N}_-]+$', unicode: true).hasMatch(profile.name)) {
      throw const VoiceProfileException(
        "name may contain only letters, digits, '-' and '_'",
      );
    }
    final dest = File(p.join(dir, '${profile.name}.json'));
    if (await dest.exists() && !force) {
      throw VoiceProfileException(
        '${dest.path} already exists (use force to overwrite)',
      );
    }
    VoiceProfile.fromJson(profile.toJson(), name: profile.name);
    await Directory(dir).create(recursive: true);
    await dest.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(profile.toJson())}\n',
    );
    return dest;
  }
}
