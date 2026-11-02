// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../audio/cancel_token.dart';
import '../audio/ffmpeg_filters.dart';
import '../audio/ffmpeg_service.dart';
import '../epub/epub_reader.dart';
import '../epub/section_extractor.dart';
import '../glossary/pronunciation_files.dart';
import '../text/chunker.dart';
import '../text/py_text.dart';
import '../text/pronunciation_applier.dart';
import '../text/roman_numerals.dart';
import '../tts/tts_engine.dart';
import '../voice/voice_settings.dart';
import 'pipeline_event.dart';

/// Where one conversion reads and writes. Mirrors `--work`, `--out` and `--log` of epub_to_kokoro.py.
class PipelineJob {
  PipelineJob({
    required this.epubPath,
    required this.workDir,
    required this.outPath,
    this.logPath,
    this.pronunciations = const {},
    this.voice = const VoiceSettings(),
    this.romanNumerals = true,
    this.profileName,
  });

  final String epubPath;

  /// Chapter FLACs, chunk files, concat lists, voice_settings.json and convert.log live here.
  final String workDir;

  /// The finished audiobook (.m4b).
  final String outPath;

  /// Default: `<workDir>/convert.log`.
  final String? logPath;

  /// Already layered (later files win) and without blank rows.
  final PronunciationTable pronunciations;
  final VoiceSettings voice;
  final bool romanNumerals;
  final String? profileName;
}

/// Port of `main()` in epub_to_kokoro.py: resumable, sequential, emitting [PipelineEvent]s.
///
/// Resume needs no state beyond the files on disk: a finished `chapter_XX.flac` is skipped, a non-empty
/// `chapter_XX_part_YYY.flac` is reused, and nothing is ever written under its final name until complete.
class PipelineRunner {
  PipelineRunner(
    this.job, {
    required this.engine,
    this.ffmpeg = const FfmpegService(),
    CancelToken? cancel,
    DateTime Function()? now,
  }) : cancel = cancel ?? CancelToken(),
       _now = now ?? DateTime.now;

  final PipelineJob job;
  final TtsEngine engine;
  final FfmpegService ffmpeg;
  final CancelToken cancel;
  final DateTime Function() _now;

  late final StreamController<PipelineEvent> _events;
  IOSink? _logSink;

  /// Starts the run when listened to. The stream always ends with Finished, Failed or Cancelled.
  Stream<PipelineEvent> run() {
    _events = StreamController<PipelineEvent>(onListen: _start);
    return _events.stream;
  }

  Future<void> _start() async {
    try {
      await _run();
    } on CancelledException {
      _emit(const Cancelled());
    } on TtsException catch (e) {
      _log('ERROR: ${e.message}${e.hint == null ? '' : ' ${e.hint}'}');
      _emit(Failed(e.message, hint: e.hint));
    } on FfmpegException catch (e) {
      _emit(Failed(e.toString()));
    } on FfmpegNotFound catch (e) {
      _emit(Failed(e.toString()));
    } on FileSystemException catch (e) {
      _emit(Failed('${e.message}: ${e.path}'));
    } finally {
      await _logSink?.flush();
      await _logSink?.close();
      await _events.close();
    }
  }

  void _emit(PipelineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  void _log([String msg = '']) {
    final t = _now();
    final clock = '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    final line = msg.isEmpty ? '' : '$clock $msg';
    _logSink?.writeln(
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)} $line',
    );
    _emit(LogLine(line));
  }

  void _checkCancelled() {
    if (cancel.isCancelled) throw const CancelledException();
  }

  Future<void> _run() async {
    final started = _now();
    final workDir = Directory(job.workDir);
    await workDir.create(recursive: true);
    _logSink = File(
      job.logPath ?? p.join(job.workDir, 'convert.log'),
    ).openWrite(mode: FileMode.append);

    final book = await EpubReader.open(job.epubPath);
    final sections = const SectionExtractor().extract(book);
    if (sections.isEmpty) {
      _emit(const Failed('No readable sections found.'));
      return;
    }
    _emit(SectionsFound(sections));
    _log('${sections.length} sections:');
    for (final s in sections) {
      _log(
        '  ${_two(s.index)}  ${cpLen(s.text).toString().padLeft(6)} chars  ${s.title}',
      );
    }

    await engine.prepare();
    final settings = {...job.voice.toJson(), ...engine.settingsExtras};
    _log(
      'Logging to ${job.logPath ?? p.join(job.workDir, 'convert.log')}; engine ${engine.id}; '
      'profile ${job.profileName ?? '(none)'}; ${settings.entries.map((e) => '${e.key} ${_py(e.value)}').join(', ')}',
    );
    await _checkVoiceSettings(settings);

    final fx = job.voice.fx
        ? (job.voice.pitch, job.voice.tempo, job.voice.bassDb)
        : null;
    final applier = PronunciationApplier(job.pronunciations);
    final hits = <String, int>{}, romanHits = <String, int>{};
    final chapterFiles = <String>[], titles = <String>[];

    String chapterPath(int i) => p.join(job.workDir, 'chapter_${_two(i)}.flac');
    var todoChars = 0;
    for (final s in sections) {
      if (!File(chapterPath(s.index)).existsSync()) todoChars += cpLen(s.text);
    }
    var doneChars = 0;

    for (final s in sections) {
      _checkCancelled();
      final i = s.index;
      final chapter = chapterPath(i);
      chapterFiles.add(chapter);
      titles.add(s.title);
      if (File(chapter).existsSync()) {
        _log('[$i/${sections.length}] ${s.title}: already done, skipping');
        _emit(ChapterSkipped(i, s.title));
        continue;
      }
      var spoken = applier.apply(s.text, hits: hits);
      if (job.romanNumerals) {
        spoken = expandRomanNumerals(spoken, hits: romanHits);
      }
      final chunks = chunkText(spoken);
      _log(
        '[$i/${sections.length}] ${s.title}: ${cpLen(s.text)} chars, ${chunks.length} chunks',
      );
      final chapterStart = _now();
      final chunkFiles = <String>[];
      for (final (k, chunk) in chunks.indexed) {
        _checkCancelled();
        final j = k + 1;
        final label = 'chunk $j/${chunks.length}';
        final cf = File(
          p.join(
            job.workDir,
            'chapter_${_two(i)}_part_${j.toString().padLeft(3, '0')}.flac',
          ),
        );
        if (cf.existsSync() && cf.statSync().size > 0) {
          // reuse chunks from an interrupted run
          _log('    $label: reusing existing file');
          _emit(ChunkReused(i, j, chunks.length));
        } else {
          _emit(ChunkStarted(i, j, chunks.length));
          final t0 = _now();
          await engine.synthesizeToFile(
            text: chunk,
            voice: job.voice,
            dest: cf,
            cancel: cancel,
            onLog: (m) => _log('    $label: $m'),
          );
          final took = _now().difference(t0);
          _log(
            '    $label: ${cpLen(chunk)} chars in ${fmtSecs(took.inSeconds)}',
          );
          _emit(ChunkDone(i, j, cpLen(chunk), took));
        }
        chunkFiles.add(cf.path);
      }
      await ffmpeg.concatToChapter(
        chunkFiles,
        chapter,
        job.workDir,
        fx: fx,
        cancel: cancel,
        onLog: _log,
      );
      for (final cf in chunkFiles) {
        File(cf).deleteSync();
      }
      doneChars += cpLen(s.text);
      final elapsed = _now().difference(started);
      final etaSecs = doneChars > 0
          ? elapsed.inMicroseconds / 1e6 / doneChars * (todoChars - doneChars)
          : 0.0;
      final audio = await ffmpeg.probeDuration(chapter);
      _log(
        '[$i/${sections.length}] ${s.title}: done in ${fmtSecs(_now().difference(chapterStart).inSeconds)}, '
        '${fmtSecs(audio)} of audio. Elapsed ${fmtSecs(elapsed.inSeconds)}, about ${fmtSecs(etaSecs)} left',
      );
      _emit(
        ChapterDone(i, s.title, _seconds(audio), elapsed, _seconds(etaSecs)),
      );
    }

    if (job.pronunciations.isNotEmpty) {
      _log(
        'Pronunciations applied this run: ${_mostCommon(hits).isEmpty ? 'none' : _mostCommon(hits)}',
      );
    }
    if (romanHits.isNotEmpty) {
      _log('Roman numerals spelled out this run: ${_mostCommon(romanHits)}');
    }

    _checkCancelled();
    _log('Combining chapters...');
    _emit(const Combining());
    await ffmpeg.combine(
      chapterFiles,
      titles,
      job.outPath,
      job.workDir,
      cancel: cancel,
      onLog: _log,
    );
    var total = 0.0;
    for (final f in chapterFiles) {
      total += await ffmpeg.probeDuration(f);
    }
    final markers = await ffmpeg.probeChapterCount(job.outPath);
    final bytes = File(job.outPath).lengthSync();
    _log(
      'Done: ${job.outPath} (${(bytes / 1e6).toStringAsFixed(1)} MB, ${fmtSecs(total)} of audio, '
      '$markers chapter markers, ${fmtSecs(_now().difference(started).inSeconds)} this run)',
    );
    _emit(Finished(job.outPath, bytes, _seconds(total), markers));
  }

  Duration _seconds(num s) => Duration(microseconds: (s * 1e6).round());

  /// "w xN, ..." sorted by count, ties in first-seen order (Python's `Counter.most_common`).
  String _mostCommon(Map<String, int> counts) {
    final entries = counts.entries.toList();
    final sorted = [for (final (i, e) in entries.indexed) (i, e)]
      ..sort(
        (a, b) => b.$2.value != a.$2.value
            ? b.$2.value.compareTo(a.$2.value)
            : a.$1.compareTo(b.$1),
      );
    return sorted.map((e) => '${e.$2.key} x${e.$2.value}').join(', ');
  }

  /// Python repr-ish for the "Logging to" line (`True`/`False`, bare numbers).
  String _py(Object? v) => v is bool ? (v ? 'True' : 'False') : '$v';

  /// Port of `check_voice_settings`: remember the settings used for this book; warn if a rerun uses different
  /// ones, because chapters already finished would then be in a different voice from the rest. Numbers
  /// compare as `num` (JSON may give 1 where 1.0 was stored).
  Future<void> _checkVoiceSettings(Map<String, Object?> settings) async {
    final record = File(p.join(job.workDir, 'voice_settings.json'));
    if (record.existsSync()) {
      Map<String, dynamic> old;
      try {
        final decoded = jsonDecode(await record.readAsString());
        old = decoded is Map<String, dynamic> ? decoded : {};
      } on FormatException {
        old = {};
      }
      final diff = <String, (Object?, Object?)>{};
      settings.forEach((k, v) {
        final o = old[k];
        if (o != v) diff[k] = (o, v); // 1 == 1.0 holds for num
      });
      if (diff.isNotEmpty) {
        _log(
          'WARNING: voice settings differ from the ones this book was started with: '
          '${diff.entries.map((e) => '${e.key} ${_repr(e.value.$1)} -> ${_repr(e.value.$2)}').join('; ')}',
        );
        _log(
          '         finished chapters keep the old voice. Delete their chapter_XX.flac files to redo them, '
          'or delete ${p.basename(record.path)} to accept the new settings.',
        );
        _emit(SettingsMismatch(diff));
      }
      return;
    }
    await record.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(settings)}\n',
    );
  }

  String _repr(Object? v) =>
      v == null ? 'None' : (v is String ? "'$v'" : _py(v));
}
