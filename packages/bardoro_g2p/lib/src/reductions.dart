// SPDX-License-Identifier: GPL-3.0-or-later

import 'phone.dart';

/// Words in running text, as the facade hands them to the sentence-level pass.
class SentenceWord {
  SentenceWord(this.text, this.phones, {this.fromRules = false, this.pausedAfter = false});

  /// The word as written.
  final String text;

  /// Phones for the word; the pass may replace them.
  List<Phone> phones;

  /// True when the phones came from the letter-to-sound rules (the lexicon already has flaps).
  final bool fromRules;

  /// True when punctuation or the end of text follows (no liaison across it).
  final bool pausedAfter;
}

/// Part-of-speech cues for the few lexicon heteronyms (`live`, `wind`, ...): the previous word
/// decides between the lexicon's POS variants. Only used when the lexicon has a variant.
String? posCue(String? previousWord) {
  if (previousWord == null) return null;
  final w = previousWord.toLowerCase();
  if (const {
    'to', 'will', 'would', 'can', 'could', 'shall', 'should', 'may', 'might', 'must', 'not',
    'let', 'i', 'you', 'we', 'they', //
  }.contains(w)) {
    return 'VERB';
  }
  if (const {
    'the', 'a', 'an', 'this', 'that', 'these', 'those', 'my', 'your', 'his', 'her', 'its', 'our',
    'their', 'some', 'any', 'no', 'every', //
  }.contains(w)) {
    return 'NOUN';
  }
  return null;
}

/// Sentence-level pass over resolved words.
///
/// - **Articles:** `a` is the schwa-like `ɐ` (the lexicon holds the letter name), `the` is `ðə`
///   before a consonant and `ði` before a vowel or a pause. Behaviour modelled on misaki's
///   handling; unverified by ear.
/// - **Flapping:** `t` between a vowel and an unstressed vowel becomes `ɾ` in words that came
///   from the rules (American English; lexicon entries already carry their flaps).
class Reductions {
  const Reductions({this.articles = true, this.flap = true});

  final bool articles;
  final bool flap;

  void apply(List<SentenceWord> words) {
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (articles) _article(words, i);
      if (flap && w.fromRules) w.phones = flapped(w.phones);
    }
  }

  void _article(List<SentenceWord> words, int i) {
    final w = words[i];
    final lower = w.text.toLowerCase();
    if (lower == 'a' && !w.pausedAfter) {
      w.phones = const [Phone('ɐ')];
    } else if (lower == 'the') {
      final next = i + 1 < words.length && !w.pausedAfter ? words[i + 1] : null;
      final startsWithVowel = next != null && next.phones.isNotEmpty && next.phones.first.isVowel;
      final beforeConsonant = next != null && next.phones.isNotEmpty && !startsWithVowel;
      w.phones = [const Phone('ð'), Phone(beforeConsonant ? 'ə' : 'i')];
    }
  }

  /// Word-internal flapping of `t` only. Flapping `d` as well was tried and measured worse against
  /// both the lexicon and espeak-ng (the `ɾ→d` confusion was the 8th most common error), so `d` stays.
  /// Public for tests.
  static List<Phone> flapped(List<Phone> phones) {
    final out = [...phones];
    for (var i = 1; i < out.length - 1; i++) {
      final p = out[i];
      if (p.symbol != 't') continue;
      final prev = out[i - 1];
      final next = out[i + 1];
      final after = prev.isVowel || prev.symbol == 'ɹ';
      if (after && next.isVowel && next.stress == 0) out[i] = const Phone('ɾ');
    }
    return out;
  }
}
