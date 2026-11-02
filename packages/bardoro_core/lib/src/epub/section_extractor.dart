// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:path/path.dart' as p;

import '../text/py_text.dart';
import '../text/stray.dart';
import 'epub_reader.dart';

/// One thing that gets read aloud: prologue, chapter, interlude, epilogue...
class Section {
  const Section({required this.index, required this.title, required this.text});

  /// 1-based; becomes chapter_XX.flac
  final int index;
  final String title;

  /// For image-titled chapters this already starts with "Title.\n".
  final String text;

  @override
  String toString() => 'Section($index, $title, ${cpLen(text)} chars)';
}

// ---------------------------------------------------------------- settings (keep together, like the Python)
/// Sections matching neither pattern are kept only if at least this long.
const int minCharsOther = 3000;

const _w = pyWordClass;
const _ws = pyWhitespaceClass;

/// Sections to read even if short (matched against the start of the section text). `\b` is a lookahead
/// because Dart's `\b` is ASCII-only.
final RegExp includeRe = RegExp(
  '^[^$_w]*(prologue|prelude|chapter|epilogue|interlude|introduction|foreword|preface|afterword|'
  'part[$_ws]+[$_w]+|'
  'book[$_ws]+(?:[ivxlc]+|\\p{Nd}+|one|two|three|four|five|six|seven|eight|nine|ten))(?![$_w])',
  caseSensitive: false,
  unicode: true,
);

/// Sections to skip (front/back matter).
final RegExp skipRe = RegExp(
  '^[^$_w]*(contents|table of contents|copyright|about the author|acknowledg[$_w]*|dedication|'
  'also by|notes|praise|title page|cover|map|glossary|discussion)(?![$_w])',
  caseSensitive: false,
  unicode: true,
);
// ------------------------------------------------------------------------------------------------

final RegExp _sentenceEnd = RegExp('(?<=[.!?:])[$_ws]', unicode: true);
final RegExp _bookOrPart = RegExp(
  '^(?:book|part)[$_ws]+[^$_ws]+\$',
  caseSensitive: false,
  unicode: true,
);
final RegExp _tocSuffix = RegExp('[-–]\\([^\\n]*\\)\$', unicode: true);
final RegExp _asciiDigits = RegExp(r'^[0-9]+$');

class SectionExtractor {
  const SectionExtractor();

  /// Port of `extract_sections`: [(title, text)] in spine order, filtered to real story sections.
  List<Section> extract(EpubBook book) {
    final sections = <Section>[];
    var lastNumber = 0;
    for (final idref in book.spine) {
      final item = book.itemWithId(idref);
      if (item == null) continue;
      final lowerName = item.name.toLowerCase();
      if (!(lowerName.endsWith('.html') ||
          lowerName.endsWith('.xhtml') ||
          lowerName.endsWith('.htm'))) {
        continue;
      }

      final nodes = documentNodes(item);
      final items = <(String, String)>[];
      for (final el in descendantElements(nodes)) {
        const tags = {'h1', 'h2', 'h3', 'p'};
        if (!tags.contains(el.localName)) continue;
        final strings = textNodes(el).map(pyStrip).where((s) => s.isNotEmpty);
        final t = cleanStray(strings.join(' '));
        if (t.isNotEmpty) items.add((el.localName!, t));
      }
      final paras = [for (final (_, t) in items) t];
      var text = paras.join('\n');
      if (text.isEmpty) continue;
      final head = cpPrefix(text, 200);
      if (skipRe.hasMatch(head)) continue;
      if (!includeRe.hasMatch(head) && cpLen(text) < minCharsOther) continue;

      String title;
      if (const {'h1', 'h2', 'h3'}.contains(items[0].$1)) {
        final m = _sentenceEnd.firstMatch(paras[0]);
        final firstSentence = m == null
            ? paras[0]
            : paras[0].substring(0, m.start);
        title = pyStripChars(cpPrefix(firstSentence, 60), ' .:');
        // "Book I" / "Part 2" followed by its own subtitle heading: keep both ("Book I: The Human Component")
        if (_bookOrPart.hasMatch(title) &&
            items.length > 1 &&
            const {'h1', 'h2', 'h3'}.contains(items[1].$1) &&
            cpLen(items[1].$2) <= 60) {
          final sub = pyStripChars(items[1].$2, ' .:');
          title = '$title: ${pyIsUpper(sub) ? cleanTitleCase(sub) : sub}';
        }
        if (title.isEmpty) title = 'Section ${sections.length + 1}';
      } else {
        var alt = '';
        for (final img in descendantElements(
          nodes,
        ).where((e) => e.localName == 'img')) {
          final a = pyStrip(img.attributes['alt'] ?? '');
          if (_asciiDigits.hasMatch(a)) {
            alt = a;
            break;
          }
        }
        title = pyStrip(
          (book.tocTitles[p.posix.basename(item.name)] ?? '').replaceAll(
            _tocSuffix,
            '',
          ),
        );
        if (title.isEmpty) {
          // chapter number: the image's alt text, else one more than the previous chapter
          lastNumber = alt.isNotEmpty ? int.parse(alt) : lastNumber + 1;
          title = 'Chapter $lastNumber';
        }
        text = '$title.\n$text'; // the title is not in the text, so say it
      }
      sections.add(
        Section(
          index: sections.length + 1,
          title: pyIsUpper(title) ? cleanTitleCase(title) : title,
          text: text,
        ),
      );
    }
    return sections;
  }
}
