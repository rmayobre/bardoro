// SPDX-License-Identifier: GPL-3.0-or-later

import 'kokoro_mapper.dart';
import 'phone.dart';
import 'word_pipeline.dart';

sealed class TextSegment {
  const TextSegment();
}

class PlainText extends TextSegment {
  const PlainText(this.text);
  final String text;
}

/// `[word](/ipa/)` in the source text: use these phonemes, ask no other tier.
class OverrideWord extends TextSegment {
  const OverrideWord(this.word, this.ipa);
  final String word;
  final String ipa;
}

/// Markup that looks like an override but is not one we support (for example `[word](+1)`).
class UnsupportedMarkup extends TextSegment {
  const UnsupportedMarkup(this.text);
  final String text;
}

final _link = RegExp(r'\[([^\[\]]*)\]\(([^()]*)\)');

/// Splits [text] into plain text, `[word](/ipa/)` overrides and unsupported `[..](..)` markup.
/// The unsupported markup is returned as its own segment so the caller can report it; it is
/// never silently turned into speech.
List<TextSegment> splitOverrides(String text) {
  final out = <TextSegment>[];
  var last = 0;
  for (final m in _link.allMatches(text)) {
    if (m.start > last) out.add(PlainText(text.substring(last, m.start)));
    final target = m[2]!;
    if (target.length >= 2 && target.startsWith('/') && target.endsWith('/') && m[1]!.isNotEmpty) {
      out.add(OverrideWord(m[1]!, target.substring(1, target.length - 1)));
    } else {
      out.add(UnsupportedMarkup(m[0]!));
    }
    last = m.end;
  }
  if (last < text.length) out.add(PlainText(text.substring(last)));
  return out;
}

class OverrideResult {
  const OverrideResult(this.phones, this.dropped);
  final WordPhones phones;

  /// Characters of the override that are not in Kokoro's vocab (removed, reported).
  final List<String> dropped;
}

/// Maps an override's phonemes into Kokoro's vocab. The IPA may already be in Kokoro/misaki
/// notation (`kˈOkəɹO`) or generic IPA (`kˈoʊkəɹoʊ`); both give the same result.
OverrideResult resolveOverride(OverrideWord o, KokoroMapper mapper) {
  final mapped = mapper.fromIpa(o.ipa);
  return OverrideResult(WordPhones(parsePhones(mapped.text), Source.override), mapped.dropped);
}
