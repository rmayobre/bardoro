// SPDX-License-Identifier: GPL-3.0-or-later

/// Internal phone inventory.
///
/// Internal phones are already Kokoro/misaki-US symbols (one code unit each), so lexicon entries,
/// rules and stress all work on the same alphabet the model reads. Generic IPA (for example from
/// `[word](/ipa/)` overrides or an espeak oracle) goes through `KokoroMapper.fromIpa` first.
///
/// Diphthongs are single symbols: `A`=eɪ, `I`=aɪ, `O`=oʊ, `W`=aʊ, `Y`=ɔɪ (verified against the
/// `hexgrad/Kokoro-82M` vocab, see `test/vocab_test.dart`).
const vowelSymbols = {
  'A', 'I', 'O', 'W', 'Y', // diphthongs
  'i', 'u', 'æ', 'ɑ', 'ɔ', 'ə', 'ɛ', 'ɜ', 'ɪ', 'ʊ', 'ʌ', // monophthongs
  'ᵻ', 'ᵊ', // reduced ɪ and syllabic schwa
};

const consonantSymbols = {
  'b', 'd', 'f', 'h', 'j', 'k', 'l', 'm', 'n', 'p', 's', 't', 'v', 'w', 'z', //
  'ð', 'ŋ', 'ɡ', 'ɹ', 'ɾ', 'ʃ', 'ʒ', 'ʔ', 'ʤ', 'ʧ', 'θ',
};

/// Every symbol rules and the lexicon may use.
final phoneInventory = {...vowelSymbols, ...consonantSymbols};

const primaryStressMark = 'ˈ';
const secondaryStressMark = 'ˌ';

class Phone {
  const Phone(this.symbol, {this.stress = 0});

  final String symbol;

  /// 0 none, 1 primary, 2 secondary. Only meaningful on vowels.
  final int stress;

  bool get isVowel => vowelSymbols.contains(symbol);

  Phone withStress(int s) => Phone(symbol, stress: s);

  @override
  bool operator ==(Object other) =>
      other is Phone && other.symbol == symbol && other.stress == stress;

  @override
  int get hashCode => Object.hash(symbol, stress);

  @override
  String toString() => '${stress == 1 ? 'ˈ' : stress == 2 ? 'ˌ' : ''}$symbol';
}

/// Parses a misaki-style string (`kˈʌz`) into phones. A stress mark applies to the next phone.
/// Characters outside [phoneInventory] (spaces, punctuation) are kept as stress-0 phones so nothing
/// is lost; callers decide what to do with them.
List<Phone> parsePhones(String text) {
  final out = <Phone>[];
  var stress = 0;
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    if (ch == primaryStressMark) {
      stress = 1;
    } else if (ch == secondaryStressMark) {
      stress = 2;
    } else {
      out.add(Phone(ch, stress: stress));
      stress = 0;
    }
  }
  return out;
}

/// Inverse of [parsePhones]: the stress mark goes immediately before the stressed vowel.
String renderPhones(Iterable<Phone> phones) =>
    phones.map((p) => p.toString()).join();
