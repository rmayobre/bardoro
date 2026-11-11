// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bardoro_services/bardoro_services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state/app_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _url = TextEditingController(text: _s.kokoroUrl);
  late final _workspace = TextEditingController(text: _s.workspaceDir);
  late final _ffmpeg = TextEditingController(text: _s.ffmpegPath);
  late final _ffprobe = TextEditingController(text: _s.ffprobePath);
  bool _saved = false;

  AppSettings get _s => widget.controller.settings.value;

  @override
  void dispose() {
    _url.dispose();
    _workspace.dispose();
    _ffmpeg.dispose();
    _ffprobe.dispose();
    super.dispose();
  }

  Future<void> _pickWorkspace() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the Bardoro workspace folder',
    );
    if (dir != null) setState(() => _workspace.text = dir);
  }

  Future<void> _save() async {
    await widget.controller.saveSettings(
      _s.copyWith(
        kokoroUrl: _url.text.trim(),
        workspaceDir: _workspace.text.trim().isEmpty ? null : _workspace.text.trim(),
        ffmpegPath: _ffmpeg.text.trim().isEmpty ? 'ffmpeg' : _ffmpeg.text.trim(),
        ffprobePath: _ffprobe.text.trim().isEmpty ? 'ffprobe' : _ffprobe.text.trim(),
      ),
    );
    if (mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kokoro server', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _url,
                  onChanged: (_) => setState(() => _saved = false),
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://your-kokoro-server',
                    helperText: 'A Kokoro-FastAPI server you run yourself. Never stored in the workspace.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Workspace', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _workspace,
                  onChanged: (_) => setState(() => _saved = false),
                  decoration: InputDecoration(
                    labelText: 'Folder',
                    helperText: 'Holds books/, voices/, glossaries/ and output/. '
                        'Shared with the Python command-line tools.',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Browse',
                      icon: const Icon(Icons.folder_open),
                      onPressed: _pickWorkspace,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('ffmpeg', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _ffmpeg,
                  onChanged: (_) => setState(() => _saved = false),
                  decoration: const InputDecoration(
                    labelText: 'ffmpeg',
                    helperText: 'Use a full path if the app cannot find it (macOS apps do not see Homebrew\'s PATH).',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ffprobe,
                  onChanged: (_) => setState(() => _saved = false),
                  decoration: const InputDecoration(
                    labelText: 'ffprobe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    FilledButton(onPressed: _save, child: const Text('Save')),
                    const SizedBox(width: 12),
                    if (_saved) const Text('Saved'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
