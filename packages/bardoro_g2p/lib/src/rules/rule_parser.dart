// SPDX-License-Identifier: GPL-3.0-or-later

import '../phone.dart';

/// Thrown for a malformed rule file; [line] is 1-based.
class RuleParseException implements Exception {
  RuleParseException(this.line, this.message);
  final int line;
  final String message;

  @override
  String toString() => 'rules line $line: $message';
}

/// `left (grapheme) right => phones`, compiled.
class Rule {
  Rule({
    required this.grapheme,
    required this.leftSource,
    required this.rightSource,
    required this.out,
    required this.line,
    required this.section,
  }) : left = leftSource.isEmpty ? null : RegExp('(?:$leftSource)\$'),
       right = rightSource.isEmpty ? null : RegExp('(?:$rightSource)');

  final String grapheme;
  final String leftSource;
  final String rightSource;
  final RegExp? left;
  final RegExp? right;

  /// Phone symbols; empty means the grapheme is silent.
  final List<String> out;
  final int line;

  /// Last `# --- name` heading above the rule (for per-section reports).
  final String section;

  bool matches(String w, int i) {
    if (!w.startsWith(grapheme, i)) return false;
    if (left != null && !left!.hasMatch(w.substring(0, i))) return false;
    if (right != null && right!.matchAsPrefix(w, i + grapheme.length) == null) {
      return false;
    }
    return true;
  }

  @override
  String toString() => 'line $line: $leftSource ($grapheme) $rightSource => ${out.join(' ')}';
}

/// Immutable rule index: candidates per first letter, longest grapheme first, then file order.
class RuleSet {
  RuleSet(Iterable<Rule> rules)
    : rules = List.unmodifiable(rules),
      _byFirst = _index(rules);

  final List<Rule> rules;
  final Map<String, List<Rule>> _byFirst;

  static Map<String, List<Rule>> _index(Iterable<Rule> rules) {
    final grouped = <String, List<(int, Rule)>>{};
    var n = 0;
    for (final r in rules) {
      (grouped[r.grapheme[0]] ??= []).add((n++, r));
    }
    // List.sort is not stable, so the file position is an explicit tiebreaker.
    return {
      for (final e in grouped.entries)
        e.key: List.unmodifiable(
          (e.value..sort((a, b) {
                final c = b.$2.grapheme.length.compareTo(a.$2.grapheme.length);
                return c != 0 ? c : a.$1.compareTo(b.$1);
              }))
              .map((p) => p.$2),
        ),
    };
  }

  /// Rules whose grapheme starts with [ch], in priority order.
  List<Rule> candidates(String ch) => _byFirst[ch] ?? const [];

  Set<String> get sections => {for (final r in rules) r.section};
}

/// Parses the rule DSL (`assets/en_us.rules`).
///
/// Syntax, one item per line, `#` starts a comment (a comment of the form `# --- name` also names
/// the section that following rules belong to):
///
///     class NAME = a b c            single-character class; `@NAME` expands to `[abc]`
///     left (grapheme) right => p h o n e s
///
/// Contexts are whitespace-separated tokens of: letters, `@NAME`, `^` (word start, left context
/// only), `$` (word end, right context only), and the quantifiers `?` `*` `+` which bind to the
/// single preceding letter or class. `|` separates whole alternatives of one context. There are no
/// groups. Output phones are space separated, must be in [phoneInventory], and an empty output
/// means silent. Rules never write stress; the stress assigner does.
class RuleParser {
  RuleParser({Set<String>? allowedPhones}) : allowed = allowedPhones ?? phoneInventory;

  final Set<String> allowed;
  static final _className = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

  RuleSet parse(String text) {
    final classes = <String, String>{};
    final rules = <Rule>[];
    var section = '';
    final lines = text.split('\n');
    for (var n = 0; n < lines.length; n++) {
      final lineNo = n + 1;
      var line = lines[n];
      final hash = line.indexOf('#');
      if (hash >= 0) {
        final comment = line.substring(hash + 1).trim();
        if (comment.startsWith('--- ')) section = comment.substring(4).trim();
        line = line.substring(0, hash);
      }
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('class ')) {
        final m = RegExp(r'^class\s+(\S+)\s*=\s*(.*)$').firstMatch(line);
        if (m == null || !_className.hasMatch(m[1]!)) {
          throw RuleParseException(lineNo, 'bad class definition: $line');
        }
        final chars = m[2]!.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (chars.isEmpty || chars.any((c) => c.runes.length != 1)) {
          throw RuleParseException(lineNo, 'class members must be single characters');
        }
        if (classes.containsKey(m[1])) {
          throw RuleParseException(lineNo, 'class ${m[1]} defined twice');
        }
        classes[m[1]!] = '[${chars.join()}]';
        continue;
      }

      final arrow = line.indexOf('=>');
      if (arrow < 0) throw RuleParseException(lineNo, 'missing "=>"');
      final lhs = RegExp(r'^(.*?)\(([^()\s]+)\)(.*)$').firstMatch(line.substring(0, arrow));
      if (lhs == null) throw RuleParseException(lineNo, 'need exactly one (grapheme)');
      final out = line
          .substring(arrow + 2)
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      for (final p in out) {
        if (!allowed.contains(p)) {
          throw RuleParseException(lineNo, 'phone "$p" is not in the phone inventory');
        }
      }
      rules.add(
        Rule(
          grapheme: lhs[2]!,
          leftSource: _context(lhs[1]!, classes, lineNo, isLeft: true),
          rightSource: _context(lhs[3]!, classes, lineNo, isLeft: false),
          out: out,
          line: lineNo,
          section: section,
        ),
      );
    }
    return RuleSet(rules);
  }

  String _context(String ctx, Map<String, String> classes, int lineNo, {required bool isLeft}) {
    final sb = StringBuffer();
    for (final token in ctx.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
      final runes = token.runes.map(String.fromCharCode).toList();
      for (var i = 0; i < runes.length; i++) {
        final c = runes[i];
        switch (c) {
          case '@':
            final m = RegExp(r'^[A-Za-z][A-Za-z0-9_]*').firstMatch(runes.skip(i + 1).join());
            if (m == null) throw RuleParseException(lineNo, 'bare "@" in "$token"');
            final cls = classes[m[0]];
            if (cls == null) throw RuleParseException(lineNo, 'unknown class @${m[0]}');
            sb.write(cls);
            i += m[0]!.length;
          case '^':
            if (!isLeft) throw RuleParseException(lineNo, '"^" only allowed in the left context');
            sb.write('^');
          case r'$':
            if (isLeft) throw RuleParseException(lineNo, r'"$" only allowed in the right context');
            sb.write(r'$');
          case '?' || '*' || '+' || '|':
            sb.write(c);
          default:
            if (!RegExp(r"^[a-z'\-]$").hasMatch(c)) {
              throw RuleParseException(lineNo, 'unexpected "$c" in context');
            }
            sb.write(c);
        }
      }
    }
    return sb.toString();
  }
}
