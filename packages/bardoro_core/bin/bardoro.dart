// SPDX-License-Identifier: GPL-3.0-or-later
// Headless runner for the Bardoro pipeline (parity checks, CI, servers). Mirrors tools/epub_to_kokoro.py and
// tools/find_unknown_words.py, and shares their workspace layout so either tool can finish a book.
//
//   dart run bardoro convert book.epub --url https://your-kokoro-server --pronunciations words.csv
//   dart run bardoro words book.epub --out words.csv
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:bardoro_core/bardoro_core.dart';
import 'package:path/path.dart' as p;

const _usage = '''
usage:
  bardoro convert EPUB [options]    epub -> chapters -> one .m4b (resumable)
  bardoro words EPUB [options]      list words not in the English dictionary (write words.csv with --out)

Run `bardoro convert --help` or `bardoro words --help` for the options.''';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
    stdout.writeln(_usage);
    exit(argv.isEmpty ? 2 : 0);
  }
  final rest = argv.skip(1).toList();
  switch (argv.first) {
    case 'convert':
      exit(await _convert(rest));
    case 'words':
      exit(await _words(rest));
    default:
      stderr.writeln('Unknown command: ${argv.first}\n$_usage');
      exit(2);
  }
}

ArgParser _convertParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption('url', help: 'Kokoro-FastAPI base URL (default: \$KOKORO_URL)')
  ..addOption(
    'profile',
    help: 'voice profile from the voices folder (or a path to a profile .json)',
  )
  ..addOption(
    'voices-dir',
    defaultsTo: 'voices',
    help: 'folder holding voice profiles',
  )
  ..addOption('voice', help: 'Kokoro voice or blend (default $defaultVoice)')
  ..addOption('speed', help: 'server-side speed (keep near 1.0)')
  ..addOption(
    'pitch',
    help: 'pitch shift, below 1 is deeper (default $defaultPitch)',
  )
  ..addOption('tempo', help: 'final playback speed (default $defaultTempo)')
  ..addOption('bass', help: 'low-shelf bass boost in dB (default $bassGainDb)')
  ..addFlag('fx', negatable: false, help: 'force the deep-voice processing on')
  ..addFlag(
    'no-fx',
    negatable: false,
    help: 'skip the deep-voice ffmpeg post-processing',
  )
  ..addOption('out', help: 'output file; default: <epub name>.m4b')
  ..addOption(
    'work',
    help: 'folder for chapter files; default: <epub name>_chapters',
  )
  ..addOption('log', help: 'log file to append to; default: <work>/convert.log')
  ..addMultiOption(
    'pronunciations',
    abbr: 'p',
    aliases: ['glossary'],
    help:
        'file of words and how they should sound (.csv, .json or .txt); repeat the option, later files win',
  )
  ..addFlag(
    'no-roman-numerals',
    negatable: false,
    help: 'do not spell out Roman numerals',
  )
  ..addFlag(
    'list',
    negatable: false,
    help: 'only list the sections that would be read',
  )
  ..addOption('ffmpeg', defaultsTo: 'ffmpeg')
  ..addOption('ffprobe', defaultsTo: 'ffprobe');

num? _num(ArgResults r, String name) {
  final v = r[name] as String?;
  if (v == null) return null;
  final n = num.tryParse(v);
  if (n == null || n <= 0) {
    stderr.writeln('--$name must be a positive number');
    exit(2);
  }
  return n;
}

Future<int> _convert(List<String> args) async {
  final parser = _convertParser();
  final ArgResults r;
  try {
    r = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    return 2;
  }
  if (r['help'] == true || r.rest.length != 1) {
    stdout.writeln('usage: bardoro convert EPUB [options]\n\n${parser.usage}');
    return r.rest.length == 1 ? 0 : 2;
  }
  final epub = r.rest.single;
  if (!File(epub).existsSync()) {
    stderr.writeln('Epub not found: $epub');
    return 1;
  }
  final stem = p.basenameWithoutExtension(epub);
  final outPath = r['out'] as String? ?? '$stem.m4b';
  final workDir = r['work'] as String? ?? '${sanitizeSlug(stem)}_chapters';

  final VoiceProfile? profile;
  try {
    profile = r['profile'] == null
        ? null
        : await VoiceProfileRepository(
            r['voices-dir'] as String,
          ).load(r['profile'] as String);
  } on VoiceProfileException catch (e) {
    stderr.writeln(e);
    return 1;
  }
  final voice = resolveVoice(
    profile: profile,
    overrides: VoiceOverrides(
      voice: r['voice'] as String?,
      speed: _num(r, 'speed'),
      pitch: _num(r, 'pitch'),
      tempo: _num(r, 'tempo'),
      bassDb: _num(r, 'bass'),
      fx: r['fx'] as bool,
      noFx: r['no-fx'] as bool,
    ),
  );

  final ffmpeg = FfmpegService(
    ffmpeg: r['ffmpeg'] as String,
    ffprobe: r['ffprobe'] as String,
  );

  if (r['list'] as bool) {
    final sections = const SectionExtractor().extract(
      await EpubReader.open(epub),
    );
    if (sections.isEmpty) {
      stderr.writeln('No readable sections found.');
      return 1;
    }
    stdout.writeln('${sections.length} sections:');
    for (final s in sections) {
      stdout.writeln(
        '  ${s.index.toString().padLeft(2, '0')}  ${cpLen(s.text).toString().padLeft(6)} chars  ${s.title}',
      );
    }
    return 0;
  }

  final url = (r['url'] as String?) ?? Platform.environment['KOKORO_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln(
      'No Kokoro server URL. Set KOKORO_URL or pass --url https://your-server',
    );
    return 1;
  }

  var pron = <String, String>{};
  try {
    final tables = <PronunciationTable>[];
    for (final f in r['pronunciations'] as List<String>) {
      final t = await const PronunciationFileIO().load(File(f));
      stdout.writeln('Loaded ${t.length} pronunciations from $f');
      tables.add(t);
    }
    pron = layered(tables);
  } on Exception catch (e) {
    stderr.writeln(e);
    return 1;
  }

  final engine = KokoroHttpEngine(url);
  final cancel = CancelToken();
  final sub = ProcessSignal.sigint.watch().listen((_) {
    stderr.writeln(
      '\nCancelling after the current step... (finished chapters and chunks are kept)',
    );
    cancel.cancel();
  });
  var code = 0;
  try {
    final runner = PipelineRunner(
      PipelineJob(
        epubPath: epub,
        workDir: workDir,
        outPath: outPath,
        logPath: r['log'] as String?,
        pronunciations: pron,
        voice: voice,
        romanNumerals: !(r['no-roman-numerals'] as bool),
        profileName: r['profile'] as String?,
      ),
      engine: engine,
      ffmpeg: ffmpeg,
      cancel: cancel,
    );
    await for (final e in runner.run()) {
      switch (e) {
        case LogLine(:final message):
          stdout.writeln(message);
        case Failed(:final message, :final hint):
          stderr.writeln(hint == null ? message : '$message $hint');
          code = 1;
        case Cancelled():
          code = 130;
        default:
      }
    }
  } finally {
    await sub.cancel();
    await engine.dispose();
  }
  return code;
}

ArgParser _wordsParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption(
    'min-count',
    defaultsTo: '2',
    help: 'ignore words seen fewer times',
  )
  ..addOption('top', defaultsTo: '80', help: 'how many to print')
  ..addOption(
    'known',
    help: 'text file of extra words to treat as known, one per line',
  )
  ..addOption('out', help: 'save the full list as word,count,pronunciation CSV')
  ..addOption(
    'dictionary',
    help:
        'English word list (default: assets/dictionary/en_words.txt next to this package)',
  );

Future<int> _words(List<String> args) async {
  final parser = _wordsParser();
  final ArgResults r;
  try {
    r = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    return 2;
  }
  if (r['help'] == true || r.rest.length != 1) {
    stdout.writeln('usage: bardoro words EPUB [options]\n\n${parser.usage}');
    return r['help'] == true ? 0 : 2;
  }
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:bardoro_core/bardoro_core.dart'),
  );
  final dictPath =
      r['dictionary'] as String? ??
      p.join(
        p.dirname(p.dirname(lib!.toFilePath())),
        'assets',
        'dictionary',
        'en_words.txt',
      );
  if (!File(dictPath).existsSync()) {
    stderr.writeln('Word list not found: $dictPath (pass --dictionary)');
    return 1;
  }
  final known = r['known'] == null
      ? <String>{}
      : {
          for (final l in await File(r['known'] as String).readAsLines())
            if (pyStrip(l).isNotEmpty) pyStrip(l).toLowerCase(),
        };
  final minCount = int.parse(r['min-count'] as String);
  final rows = UnknownWordFinder(await WordList.fromFile(dictPath)).find(
    await EpubReader.open(r.rest.single),
    minCount: minCount,
    known: known,
  );
  if (rows.isEmpty) {
    stdout.writeln('No unknown words found.');
    return 0;
  }
  final top = int.parse(r['top'] as String);
  stdout.writeln(
    '${rows.length} unrecognised words (seen at least $minCount times). Top ${rows.length < top ? rows.length : top}:\n',
  );
  for (final w in rows.take(top)) {
    stdout.writeln('${w.count.toString().padLeft(6)}  ${w.word}');
  }
  if (r['out'] != null) {
    await File(r['out'] as String).writeAsString(wordsCsv(rows));
    stdout.writeln('\nFull list (${rows.length} words) saved to ${r['out']}');
  }
  return 0;
}
