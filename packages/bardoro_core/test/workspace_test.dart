// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:bardoro_core/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  test('paths match the CLI layout', () {
    final b = const Workspace('/w').book('some-book', epubPath: 'x.epub');
    expect(b.wordsCsv, '/w/output/some-book/words.csv');
    expect(b.chapterFlac(3), '/w/output/some-book/chapters/chapter_03.flac');
    expect(b.m4bPath, '/w/output/some-book/some-book.m4b');
    expect(b.voiceSettingsJson,
        '/w/output/some-book/chapters/voice_settings.json');
  });

  test('sanitizeSlug drops spaces and apostrophes like the Python regex', () {
    expect(sanitizeSlug("The Brothers' War - Jeff Grubb (1998)"),
        'The_Brothers_War_-_Jeff_Grubb_1998');
  });

  test('app seed assets are identical to the repo voices/ and glossaries/', () {
    final root = Directory.current.parent.parent.path;
    for (final sub in ['voices', 'glossaries']) {
      for (final f in Directory('$root/app/assets/seed/$sub').listSync()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        expect(f.readAsStringSync(), File('$root/$sub/$name').readAsStringSync(),
            reason: '$sub/$name drifted from its seed copy');
      }
    }
  });
}
