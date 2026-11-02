// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// One manifest entry. [name] is the percent-decoded href (relative to the OPF folder), like ebooklib's file_name.
class EpubItem {
  EpubItem({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.properties,
    required this.bytes,
  });

  final String id;
  final String name;
  final String mediaType;
  final Set<String> properties;
  final Uint8List Function() bytes;

  bool get isNav =>
      mediaType == 'application/xhtml+xml' && properties.contains('nav');

  /// ebooklib turns `application/xhtml+xml` items into EpubHtml and re-serialises their `<body>` children,
  /// so text directly inside `<body>` and anything in `<head>` never reaches BeautifulSoup.
  bool get isEpubHtml => mediaType == 'application/xhtml+xml';
}

/// What `extract_sections` and `find_unknown_words` need from an epub, with ebooklib's behaviour
/// (`ignore_ncx=True`): spine order, manifest order, and the table of contents from the EPUB 3 nav document,
/// falling back to the NCX only when the epub has no nav document.
class EpubBook {
  EpubBook(this.items, this.spine, this.tocTitles);

  final List<EpubItem> items;
  final List<String> spine;

  /// `{file basename: title}` (first entry for a file wins), as `toc_titles` builds it.
  final Map<String, String> tocTitles;

  EpubItem? itemWithId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Items ebooklib files under ITEM_DOCUMENT: every `application/xhtml+xml` item, nav included.
  Iterable<EpubItem> get documents => items.where((i) => i.isEpubHtml);
}

class EpubReader {
  const EpubReader();

  static Future<EpubBook> open(String path) async =>
      const EpubReader().read(await File(path).readAsBytes());

  EpubBook read(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    Uint8List read(String name) {
      final entry = archive.findFile(p.posix.normalize(name));
      if (entry == null) throw FormatException('Missing file in epub: $name');
      return Uint8List.fromList(entry.readBytes()!);
    }

    final container = XmlDocument.parse(
      utf8.decode(read('META-INF/container.xml')),
    );
    String? opfPath;
    for (final root in container.findAllElements('rootfile')) {
      if (root.getAttribute('media-type') == 'application/oebps-package+xml') {
        opfPath = root.getAttribute('full-path');
      }
    }
    if (opfPath == null) {
      throw const FormatException('No OPF rootfile in META-INF/container.xml');
    }
    final opfDir = p.posix.dirname(opfPath);
    final opf = XmlDocument.parse(_decode(read(opfPath)));

    final items = <EpubItem>[];
    final manifest = opf.findAllElements('manifest').first;
    for (final el in manifest.childElements) {
      if (el.name.local != 'item') continue;
      final href = _unquote(el.getAttribute('href') ?? '');
      final full = p.posix.normalize(p.posix.join(opfDir, href));
      items.add(
        EpubItem(
          id: el.getAttribute('id') ?? '',
          name: href,
          mediaType: el.getAttribute('media-type') ?? '',
          properties: (el.getAttribute('properties') ?? '')
              .split(' ')
              .where((s) => s.isNotEmpty)
              .toSet(),
          bytes: () => read(full),
        ),
      );
    }

    final spineEl = opf.findAllElements('spine').first;
    final spine = [
      for (final r in spineEl.childElements)
        if (r.getAttribute('idref') != null) r.getAttribute('idref')!,
    ];

    final book = EpubBook(items, spine, {});
    final nav = items.where((i) => i.isNav).firstOrNull;
    final tocAttr = spineEl.getAttribute('toc') ?? '';
    if (nav != null) {
      _parseNavToc(
        _decode(nav.bytes()),
        p.posix.dirname(nav.name),
        book.tocTitles,
      );
    } else if (tocAttr.isNotEmpty) {
      final ncx = book.itemWithId(tocAttr);
      if (ncx != null) _parseNcx(_decode(ncx.bytes()), book.tocTitles);
    }
    return book;
  }
}

String _decode(List<int> bytes) {
  final s = utf8.decode(bytes, allowMalformed: true);
  return s.startsWith('﻿') ? s.substring(1) : s;
}

/// Python `urllib.parse.unquote`: leaves invalid escapes alone.
String _unquote(String s) {
  if (!s.contains('%')) return s;
  final out = <int>[];
  final units = utf8.encode(s);
  for (var i = 0; i < units.length; i++) {
    if (units[i] == 0x25 &&
        i + 2 < units.length &&
        _hex(units[i + 1]) >= 0 &&
        _hex(units[i + 2]) >= 0) {
      out.add(_hex(units[i + 1]) * 16 + _hex(units[i + 2]));
      i += 2;
    } else {
      out.add(units[i]);
    }
  }
  return utf8.decode(out, allowMalformed: true);
}

int _hex(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

void _addToc(Map<String, String> titles, String? href, String? title) {
  if (href == null || href.isEmpty || title == null) return;
  final t = title.trim();
  if (t.isEmpty) return;
  titles.putIfAbsent(p.posix.basename(href.split('#')[0]), () => t);
}

/// ebooklib `_parse_nav(navtype="toc")`: first `<nav>` with any attribute equal to "toc"; entries are
/// `li > a`; an `li` with a nested `ol` is titled by its first child element.
void _parseNavToc(String source, String baseDir, Map<String, String> titles) {
  final doc = html_parser.parse(source);
  final nav = doc
      .querySelectorAll('nav')
      .where((n) => n.attributes.values.contains('toc'))
      .firstOrNull;
  final ol = nav?.children.where((c) => c.localName == 'ol').firstOrNull;
  if (ol == null) return;

  String? hrefOf(dom.Element a) {
    final h = a.attributes['href'];
    return (h == null || h.isEmpty)
        ? null
        : p.posix.normalize(p.posix.join(baseDir, h));
  }

  void walk(dom.Element list) {
    for (final li in list.children.where((c) => c.localName == 'li')) {
      final sub = li.children.where((c) => c.localName == 'ol').firstOrNull;
      final link = li.children.where((c) => c.localName == 'a').firstOrNull;
      if (sub != null) {
        final href = link == null ? null : hrefOf(link);
        _addToc(
          titles,
          href,
          li.children.isEmpty ? null : li.children.first.text,
        );
        walk(sub);
      } else if (link != null) {
        _addToc(titles, hrefOf(link), link.text);
      }
    }
  }

  walk(ol);
}

/// ebooklib `_parse_ncx`: navPoint label is the first child of navLabel; `src` is used as written.
void _parseNcx(String source, Map<String, String> titles) {
  final doc = XmlDocument.parse(source);
  final navMap = doc.findAllElements('navMap').firstOrNull;
  if (navMap == null) return;

  void walk(XmlElement parent) {
    for (final point in parent.childElements.where(
      (e) => e.name.local == 'navPoint',
    )) {
      String label = '';
      String content = '';
      for (final a in point.childElements) {
        if (a.name.local == 'navLabel') {
          final first = a.childElements.firstOrNull;
          label = first?.innerText ?? '';
        } else if (a.name.local == 'content') {
          content = a.getAttribute('src') ?? '';
        }
      }
      _addToc(titles, content, label);
      walk(point);
    }
  }

  walk(navMap);
}

/// Parses an item's markup the way ebooklib hands it to BeautifulSoup. For EpubHtml items only the children
/// of `<body>` survive (the text directly inside `<body>` before its first child element is dropped).
List<dom.Node> documentNodes(EpubItem item) {
  final doc = html_parser.parse(_decode(item.bytes()));
  if (!item.isEpubHtml) return doc.nodes.toList();
  final body = doc.body;
  if (body == null) return const [];
  final nodes = body.nodes.toList();
  final firstChild = nodes.indexWhere((n) => n is! dom.Text);
  return firstChild < 0 ? const [] : nodes.sublist(firstChild);
}

/// BeautifulSoup `get_text(sep, strip=...)`: text nodes only (no comments), script/style excluded.
Iterable<String> textNodes(dom.Node node) sync* {
  if (node is dom.Text) {
    yield node.data;
  } else if (node is dom.Element) {
    if (node.localName == 'script' || node.localName == 'style') return;
    for (final c in node.nodes) {
      yield* textNodes(c);
    }
  }
}

/// All elements below [nodes] in document order (the nodes themselves included).
Iterable<dom.Element> descendantElements(List<dom.Node> nodes) sync* {
  for (final n in nodes) {
    if (n is dom.Element) {
      yield n;
      yield* descendantElements(n.nodes.toList());
    }
  }
}
