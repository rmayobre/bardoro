// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal EPUB 3 in memory: [docs] maps file name -> body HTML, in spine order.
Uint8List buildEpub(
  Map<String, String> docs, {
  Map<String, String> toc = const {},
}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  final ids = {for (final (i, n) in docs.keys.indexed) n: 'd$i'};
  add('EPUB/content.opf', '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">test</dc:identifier><dc:title>Test</dc:title><dc:language>en</dc:language></metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
${docs.keys.map((n) => '<item id="${ids[n]}" href="$n" media-type="application/xhtml+xml"/>').join('\n')}
</manifest>
<spine>${docs.keys.map((n) => '<itemref idref="${ids[n]}"/>').join()}</spine>
</package>''');
  add('EPUB/nav.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol>${toc.entries.map((e) => '<li><a href="${e.key}">${e.value}</a></li>').join()}</ol></nav>
</body></html>''');
  for (final e in docs.entries) {
    add(
      'EPUB/${e.key}',
      '<?xml version="1.0" encoding="utf-8"?>\n'
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>${e.value}</body></html>',
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The three-chapter book the Python smoke test builds.
Uint8List smokeEpub() => buildEpub({
  'c1.xhtml':
      '<h1>Prologue</h1><p>Urza waited. Tocasia nodded, and the night was quiet.</p>',
  'c2.xhtml':
      "<h1>Chapter 1</h1><p>Urza's brother Mishra arrived. ${'They spoke at length. ' * 40}</p>",
  'c3.xhtml': '<h1>Epilogue</h1><p>Mishra remembered everything.</p>',
});
