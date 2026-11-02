// SPDX-License-Identifier: GPL-3.0-or-later
// Spikes S1 (does the model run through flutter_onnxruntime?) and S2 (how fast?), see docs/SPIKES.md.
// It runs once, prints a JSON report, writes results.json and WAV files into SPIKE_OUT, and exits.
//
// Environment (all paths absolute):
//   SPIKE_MODEL     kokoro-v1.0.onnx (or an int8/fp16 variant for S2)
//   SPIKE_VOICES    voices-v1.0.bin (the npz), only needed for the style-row experiment
//   SPIKE_REF       folder written by make_reference.py (NAME.tokens.json, NAME.style.f32, NAME.ref.wav, reference.json)
//   SPIKE_OUT       folder for results.json and the WAV files
//   SPIKE_PROVIDER  optional: cpu (default) | coreml | directml | cuda
//   SPIKE_THREADS   optional: intra-op threads
//   SPIKE_RUNS      optional: timed runs of the `long` case for S2 (default 5; the first is discarded)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'spike_io.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
  };
  var code = 0;
  try {
    await _run(report);
  } on Object catch (e, st) {
    report['error'] = '$e';
    report['stack'] = '$st'.split('\n').take(8).toList();
    code = 1;
  }
  final out = Platform.environment['SPIKE_OUT'];
  final json = const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln('RESULT $json');
  if (out != null) {
    Directory(out).createSync(recursive: true);
    File('$out/results.json').writeAsStringSync('$json\n');
  }
  exit(code);
}

String _env(String k) {
  final v = Platform.environment[k];
  if (v == null || v.isEmpty) {
    throw StateError('Set $k (see the header of lib/main.dart)');
  }
  return v;
}

List<OrtProvider>? _providers() =>
    switch ((Platform.environment['SPIKE_PROVIDER'] ?? 'cpu').toLowerCase()) {
      'cpu' => null,
      'coreml' => [OrtProvider.CORE_ML, OrtProvider.CPU],
      'directml' => [OrtProvider.DIRECT_ML, OrtProvider.CPU],
      'cuda' => [OrtProvider.CUDA, OrtProvider.CPU],
      final other => throw StateError('Unknown SPIKE_PROVIDER $other'),
    };

Future<void> _run(Map<String, Object?> report) async {
  final modelPath = _env('SPIKE_MODEL');
  final refDir = _env('SPIKE_REF');
  final outDir = _env('SPIKE_OUT');
  Directory(outDir).createSync(recursive: true);
  report['model'] = {'path': modelPath, 'bytes': File(modelPath).lengthSync()};
  report['provider'] = Platform.environment['SPIKE_PROVIDER'] ?? 'cpu';
  report['threads'] = Platform.environment['SPIKE_THREADS'];

  final threads = int.tryParse(Platform.environment['SPIKE_THREADS'] ?? '');
  final session = await OnnxRuntime().createSession(
    modelPath,
    options: OrtSessionOptions(
      providers: _providers(),
      intraOpNumThreads: threads,
    ),
  );
  report['inputNames'] = session.inputNames;
  report['outputNames'] = session.outputNames;
  report['inputInfo'] = await session.getInputInfo();
  report['outputInfo'] = await session.getOutputInfo();

  // names are read from the session, never hard-coded
  final tokensName = session.inputNames.firstWhere(
    (n) => n == 'tokens' || n == 'input_ids',
  );
  final styleName = session.inputNames.firstWhere((n) => n == 'style');
  final speedName = session.inputNames.firstWhere((n) => n == 'speed');

  Future<(Float32List, Duration)> infer(
    List<int> paddedTokens,
    Float32List style,
  ) async {
    final inputs = {
      tokensName: await OrtValue.fromList(Int64List.fromList(paddedTokens), [
        1,
        paddedTokens.length,
      ]),
      styleName: await OrtValue.fromList(style, [1, 256]),
      speedName: await OrtValue.fromList(Float32List.fromList([1.0]), [1]),
    };
    final sw = Stopwatch()..start();
    final outputs = await session.run(inputs);
    sw.stop();
    final audio = outputs[session.outputNames.first]!;
    final samples = Float32List.fromList([
      for (final v in await audio.asFlattenedList()) (v as num).toDouble(),
    ]);
    for (final v in [...inputs.values, ...outputs.values]) {
      await v.dispose();
    }
    return (samples, sw.elapsed);
  }

  final refs = {
    for (final r
        in jsonDecode(File('$refDir/reference.json').readAsStringSync())
            as List)
      r['name'] as String: r as Map,
  };
  Map<String, Float32List>? voices;
  final votesPath = Platform.environment['SPIKE_VOICES'];
  if (votesPath != null) voices = loadVoices(votesPath, ['am_onyx']);

  final cases = <String, Object?>{};
  for (final name in ['short', 'numbers', 'long']) {
    final tokens =
        (jsonDecode(File('$refDir/$name.tokens.json').readAsStringSync())
                as List)
            .cast<int>();
    final styleBytes = File('$refDir/$name.style.f32').readAsBytesSync();
    final style = styleBytes.buffer.asFloat32List(
      styleBytes.offsetInBytes,
      256,
    );
    final refWav = readWav('$refDir/$name.ref.wav');
    final (audio, took) = await infer(tokens, style);
    writeWav('$outDir/$name.len-1.wav', audio);
    final entry = <String, Object?>{
      'tokens': tokens.length - 2,
      'seconds': audio.length / sampleRate,
      'refSeconds': refs[name]!['ref_seconds'],
      'durationDiffPercent':
          100 * (audio.length - refWav.length) / refWav.length,
      'peak': peak(audio),
      'refPeak': peak(refWav),
      'peakDiffPercent': 100 * (peak(audio) - peak(refWav)) / peak(refWav),
      'runSeconds': took.inMicroseconds / 1e6,
      'silent': peak(audio) < 1e-4,
    };
    if (voices != null) {
      // the model card's convention: row index len(tokens) instead of len(tokens) - 1
      final pack = voices['am_onyx']!;
      final n = tokens.length - 2;
      final row = Float32List.sublistView(pack, n * 256, n * 256 + 256);
      final (alt, _) = await infer(tokens, row);
      writeWav('$outDir/$name.len.wav', alt);
      entry['altRowSeconds'] = alt.length / sampleRate;
    }
    cases[name] = entry;
  }
  report['s1'] = cases;

  // S2: real-time factor on the long case (first run is warm-up)
  final runs = int.tryParse(Platform.environment['SPIKE_RUNS'] ?? '') ?? 5;
  final tokens =
      (jsonDecode(File('$refDir/long.tokens.json').readAsStringSync()) as List)
          .cast<int>();
  final styleBytes = File('$refDir/long.style.f32').readAsBytesSync();
  final style = styleBytes.buffer.asFloat32List(styleBytes.offsetInBytes, 256);
  final times = <double>[];
  var audioSeconds = 0.0;
  for (var i = 0; i < runs; i++) {
    final (audio, took) = await infer(tokens, style);
    audioSeconds = audio.length / sampleRate;
    if (i > 0) times.add(took.inMicroseconds / 1e6);
  }
  times.sort();
  final median = times.isEmpty ? double.nan : times[times.length ~/ 2];
  report['s2'] = {
    'timedRuns': times.length,
    'audioSeconds': audioSeconds,
    'medianWallSeconds': median,
    'rtf': audioSeconds / median, // higher is faster; the pass rule is >= 2
    'hoursFor100kWordBook': (100000 / 150 / 60) / (audioSeconds / median),
  };
  await session.close();
}
