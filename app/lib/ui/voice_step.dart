// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_core/bardoro_core.dart';
import 'package:flutter/material.dart';

import '../state/book_controller.dart';
import 'snapshot_builder.dart';

/// Pick a voice profile, adjust it, and choose which series glossaries apply.
class VoiceStep extends StatelessWidget {
  const VoiceStep({super.key, required this.book});

  final BookController book;

  @override
  Widget build(BuildContext context) => SnapshotBuilder(
    snapshot: book.state,
    builder: (context, s) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Voice profile', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: s.profile,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Built-in default')),
                    for (final p in s.profiles)
                      DropdownMenuItem(
                        value: p.name,
                        child: Text(
                          p.description == null ? p.name : '${p.name} - ${p.description}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => book.selectProfile(v ?? ''),
                ),
                const SizedBox(height: 16),
                _VoiceFields(
                  // A new key rebuilds the text fields when a different profile is chosen.
                  key: ValueKey('${s.profile}-${s.voice.hashCode}'),
                  voice: s.voice,
                  onChanged: book.setVoice,
                ),
                const SizedBox(height: 24),
                Text('Glossaries', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Shared respellings for a series. Later ones win, and this book\'s own words win over all of them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (s.glossaryNames.isEmpty)
                  const Text('No glossaries in the workspace yet.')
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final g in s.glossaryNames)
                        FilterChip(
                          label: Text(g),
                          selected: s.glossaries.contains(g),
                          onSelected: (on) => book.toggleGlossary(g, on),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Spell out Roman numerals'),
                  subtitle: const Text('"Chapter XII" is read as "Chapter twelve".'),
                  value: s.romanNumerals,
                  onChanged: book.setRomanNumerals,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => book.goTo(WizardStep.convert),
                    child: const Text('Next: Convert'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _VoiceFields extends StatefulWidget {
  const _VoiceFields({super.key, required this.voice, required this.onChanged});

  final VoiceSettings voice;
  final ValueChanged<VoiceSettings> onChanged;

  @override
  State<_VoiceFields> createState() => _VoiceFieldsState();
}

class _VoiceFieldsState extends State<_VoiceFields> {
  late final _voice = TextEditingController(text: widget.voice.voice);
  late final _speed = TextEditingController(text: '${widget.voice.speed}');
  late final _pitch = TextEditingController(text: '${widget.voice.pitch}');
  late final _tempo = TextEditingController(text: '${widget.voice.tempo}');
  late final _bass = TextEditingController(text: '${widget.voice.bassDb}');
  late bool _fx = widget.voice.fx;

  @override
  void dispose() {
    for (final c in [_voice, _speed, _pitch, _tempo, _bass]) {
      c.dispose();
    }
    super.dispose();
  }

  num _num(TextEditingController c, num fallback) {
    final n = num.tryParse(c.text.trim());
    return n == null || n <= 0 ? fallback : n;
  }

  void _push() => widget.onChanged(
    VoiceSettings(
      voice: _voice.text.trim().isEmpty ? defaultVoice : _voice.text.trim(),
      speed: _num(_speed, 1.0),
      pitch: _num(_pitch, defaultPitch),
      tempo: _num(_tempo, defaultTempo),
      bassDb: _num(_bass, bassGainDb),
      fx: _fx,
    ),
  );

  Widget _field(String label, TextEditingController c, {String? help, double width = 150}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          onChanged: (_) => _push(),
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _voice,
        onChanged: (_) => _push(),
        decoration: const InputDecoration(
          labelText: 'Kokoro voice',
          helperText: 'A voice name or a blend such as am_onyx(4)+am_adam(1). Use a plain voice if the server rejects blends.',
          helperMaxLines: 2,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Deep-voice processing (ffmpeg)'),
        value: _fx,
        onChanged: (v) {
          setState(() => _fx = v);
          _push();
        },
      ),
      Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          _field('Server speed', _speed, help: 'Keep at 1.0'),
          _field('Pitch', _pitch, help: 'Below 1 is deeper'),
          _field('Tempo', _tempo, help: 'Final speed'),
          _field('Bass (dB)', _bass),
        ],
      ),
    ],
  );
}
