// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cancel_token.dart';
import 'ffmpeg_filters.dart';

class FfmpegException implements Exception {
  const FfmpegException(this.command, this.exitCode, this.stderr);

  final String command;
  final int exitCode;

  /// Full stderr. Callers log all of it; [toString] shows the tail.
  final String stderr;

  @override
  String toString() {
    final tail = stderr.length > 1500
        ? stderr.substring(stderr.length - 1500)
        : stderr;
    return 'Command failed: $command\n$tail';
  }
}

class FfmpegNotFound implements Exception {
  const FfmpegNotFound(this.executable);

  final String executable;

  @override
  String toString() =>
      '$executable was not found. Install ffmpeg or set its path.';
}

/// Thin wrapper over `ffmpeg` / `ffprobe` that always passes an argument list (no shell, so titles with spaces
/// and apostrophes are safe). Output files are written to `<stem>.part<ext>` and renamed when ffmpeg exits
/// cleanly, so a killed run never leaves something that looks finished.
class FfmpegService {
  const FfmpegService({this.ffmpeg = 'ffmpeg', this.ffprobe = 'ffprobe'});

  final String ffmpeg;
  final String ffprobe;

  /// `<stem>.part<ext>`: keeps the extension so ffmpeg still infers the container.
  static String partPath(String finalPath) =>
      '${p.withoutExtension(finalPath)}.part${p.extension(finalPath)}';

  Future<String> _run(
    String exe,
    List<String> args, {
    CancelToken? cancel,
    void Function(String message)? onLog,
  }) async {
    final Process proc;
    try {
      proc = await Process.start(exe, args);
    } on ProcessException {
      throw FfmpegNotFound(exe);
    }
    final stop = cancel?.onCancel(proc.kill);
    final out = proc.stdout.transform(utf8.decoder).join();
    final err = proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;
    stop?.call();
    final stdout = await out;
    final stderr = await err;
    if (cancel?.isCancelled ?? false) throw const CancelledException();
    if (code != 0) {
      final cmd = '$exe ${args.join(' ')}';
      onLog?.call(
        'Command failed (exit $code): $cmd\n$stderr',
      ); // full stderr goes to the log
      throw FfmpegException(cmd, code, stderr);
    }
    return stdout;
  }

  Future<String> _probe(
    String file,
    String entry, {
    bool stream = false,
  }) async {
    final out = await _run(ffprobe, [
      '-v', 'error', //
      if (stream) ...['-select_streams', 'a:0'],
      '-show_entries', entry, '-of', 'default=nw=1:nk=1', file,
    ]);
    return out.trim();
  }

  Future<int> probeSampleRate(String file) async =>
      int.parse(await _probe(file, 'stream=sample_rate', stream: true));

  /// Seconds.
  Future<double> probeDuration(String file) async =>
      double.parse(await _probe(file, 'format=duration'));

  Future<int> probeChapterCount(String file) async => (await _probe(
    file,
    'chapter=id',
  )).split('\n').where((l) => l.trim().isNotEmpty).length;

  /// Chunks -> one chapter FLAC (with the deep-voice filter when [fx] is given as (pitch, tempo, bass)).
  Future<void> concatToChapter(
    List<String> chunkFiles,
    String dest,
    String workDir, {
    (num pitch, num tempo, num bassDb)? fx,
    CancelToken? cancel,
    void Function(String message)? onLog,
  }) async {
    final list = File(
      p.join(workDir, '${p.basenameWithoutExtension(dest)}_list.txt'),
    );
    await list.writeAsString(chunkFiles.map(concatLine).join());
    final part = partPath(dest);
    final args = [
      '-y',
      '-v',
      'error',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      list.path,
      if (fx != null) ...[
        '-af',
        buildFilter(
          await probeSampleRate(chunkFiles.first),
          fx.$1,
          fx.$2,
          fx.$3,
        ),
      ],
      '-c:a',
      'flac',
      part,
    ];
    await _run(ffmpeg, args, cancel: cancel, onLog: onLog);
    await File(part).rename(dest);
  }

  /// FFMETADATA with one `[CHAPTER]` per chapter (millisecond timebase, durations from ffprobe).
  Future<String> chapterMetadata(
    List<String> chapterFiles,
    List<String> titles,
    String outPath,
  ) async {
    final meta = [
      ';FFMETADATA1',
      'title=${ffEscape(p.basenameWithoutExtension(outPath))}',
    ];
    var t = 0;
    for (var i = 0; i < chapterFiles.length; i++) {
      final durMs = ((await probeDuration(chapterFiles[i])) * 1000).toInt();
      meta.addAll([
        '[CHAPTER]', 'TIMEBASE=1/1000', 'START=$t', 'END=${t + durMs}', //
        'title=${ffEscape(titles[i])}',
      ]);
      t += durMs;
    }
    return '${meta.join('\n')}\n';
  }

  /// Chapters -> `.m4b` (AAC 96 kbps, `+faststart`, `-f ipod` for `.m4b`) with chapter markers.
  Future<void> combine(
    List<String> chapterFiles,
    List<String> titles,
    String outPath,
    String workDir, {
    CancelToken? cancel,
    void Function(String message)? onLog,
  }) async {
    final metaFile = File(p.join(workDir, 'chapters_meta.txt'));
    await metaFile.writeAsString(
      await chapterMetadata(chapterFiles, titles, outPath),
    );
    final list = File(p.join(workDir, 'all_chapters.txt'));
    await list.writeAsString(chapterFiles.map(concatLine).join());
    final part = partPath(outPath);
    await _run(
      ffmpeg,
      [
        '-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', list.path, //
        '-i',
        metaFile.path,
        '-map',
        '0:a',
        '-map_metadata',
        '1',
        '-map_chapters',
        '1',
        '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart',
        if (p.extension(outPath).toLowerCase() == '.m4b') ...['-f', 'ipod'],
        part,
      ],
      cancel: cancel,
      onLog: onLog,
    );
    await File(part).rename(outPath);
  }
}
