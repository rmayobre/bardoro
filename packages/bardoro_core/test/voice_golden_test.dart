// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

void main() {
  final units = readUnits();

  test('defaults match voice_profiles.py', () {
    final c = units['constants'] as Map<String, dynamic>;
    expect(defaultVoice, c['DEFAULT_VOICE']);
    expect(defaultPitch, c['DEFAULT_PITCH']);
    expect(defaultTempo, c['DEFAULT_TEMPO']);
    expect(bassGainDb, c['BASS_GAIN_DB']);
  });

  test('resolveVoice: precedence and every fx branch equal resolve_voice', () {
    for (final c in units['voiceResolve'] as List) {
      final prof = c['profile'] == null
          ? null
          : VoiceProfile.fromJson(c['profile'], name: 'p');
      final f = c['flags'] as Map<String, dynamic>;
      final got = resolveVoice(
        profile: prof,
        overrides: VoiceOverrides(
          voice: f['voice'] as String?,
          speed: f['speed'] as num?,
          pitch: f['pitch'] as num?,
          tempo: f['tempo'] as num?,
          bassDb: f['bass_db'] as num?,
          fx: f['fx'] == true,
          noFx: f['no_fx'] == true,
        ),
        fxDefault: c['fxDefault'] as bool,
      );
      expect(jsonEncode(got.toJson()), jsonEncode(c['settings']), reason: '$c');
    }
  });

  group('profile validation (port of validate)', () {
    void bad(Object? data, String fragment) => expect(
      () => VoiceProfile.fromJson(data, name: 'x', where: 'x.json'),
      throwsA(
        isA<VoiceProfileException>().having(
          (e) => e.message,
          'message',
          contains(fragment),
        ),
      ),
    );
    test('rejects what Python rejects', () {
      bad([], 'must contain a JSON object');
      bad({'tempoo': 1}, 'unknown key(s) tempoo');
      bad({'pitch': 0}, 'pitch must be a positive number');
      bad({'pitch': true}, 'pitch must be a positive number');
      bad({'tempo': '0.9'}, 'tempo must be a positive number');
      bad({'voice': 3}, 'voice must be text');
      bad({'voice': '  '}, 'voice must not be empty');
      bad({'fx': 'yes'}, 'fx must be true or false');
    });
    test('accepts the shipped profiles', () async {
      final repo = VoiceProfileRepository('../../voices');
      final names = (await repo.list()).map((p) => p.name).toList();
      expect(names, containsAll(['deep-narrator', 'plain-onyx']));
      final deep = await repo.load('deep-narrator');
      expect(
        resolveVoice(profile: deep).toJson()['voice'],
        'am_onyx(4)+am_adam(1)',
      );
      expect(resolveVoice(profile: await repo.load('plain-onyx')).fx, isFalse);
    });
  });

  test('repository create refuses to overwrite and bad names', () async {
    final dir = await Directory.systemTemp.createTemp('vp');
    addTearDown(() => dir.delete(recursive: true));
    final repo = VoiceProfileRepository(dir.path);
    await repo.create(
      const VoiceProfile(name: 'gravel', voice: 'am_michael', pitch: 0.9),
    );
    expect(
      () => repo.create(const VoiceProfile(name: 'gravel')),
      throwsA(isA<VoiceProfileException>()),
    );
    expect(
      () => repo.create(const VoiceProfile(name: 'bad name!')),
      throwsA(isA<VoiceProfileException>()),
    );
    expect((await repo.load('gravel')).pitch, 0.9);
    expect(() => repo.load('missing'), throwsA(isA<VoiceProfileException>()));
  });

  group('ffmpeg strings equal the Python ones', () {
    test('buildFilter', () {
      for (final c in units['buildFilter'] as List) {
        expect(
          buildFilter(
            c['sr'] as int,
            c['pitch'] as num,
            c['tempo'] as num,
            c['bass'] as num,
          ),
          c['result'],
        );
      }
    });
    test('concatLine', () {
      for (final c in units['concatLine'] as List) {
        expect(concatLine(c['path'] as String), c['line']);
      }
    });
    test('ffEscape', () {
      for (final c in units['ffEscape'] as List) {
        expect(ffEscape(c['text'] as String), c['result']);
      }
    });
    test('fmtSecs', () {
      for (final c in units['fmtSecs'] as List) {
        expect(fmtSecs(c['sec'] as num), c['result'], reason: '${c['sec']}');
      }
    });
  });
}
