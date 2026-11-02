// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import '../audio/cancel_token.dart';
import '../voice/voice_settings.dart';

/// The seam between the pipeline and wherever audio comes from: "turn this chunk of text (up to about 2,500
/// characters) into one audio file". `KokoroHttpEngine` is the first implementation (and the test oracle for
/// the embedded engine in `bardoro_kokoro_local`).
abstract interface class TtsEngine {
  /// 'kokoro-http' | 'local-onnx'
  String get id;

  /// Extra keys recorded in `voice_settings.json` beside the voice settings (empty for the HTTP engine, so the
  /// file stays identical to the CLI's). The embedded engine adds `engine` and `model`.
  Map<String, Object?> get settingsExtras;

  /// Load the model or validate the configuration. Throws [TtsException] with a user-readable reason.
  Future<void> prepare();

  /// Words the engine could not phonemize (embedded engine; always empty for HTTP).
  Set<String> get unresolvedWords;

  /// Turn one chunk of text into a FLAC file at [dest]. Must not leave a partial file at [dest]: write to
  /// `<dest>.part` and rename when complete.
  Future<void> synthesizeToFile({
    required String text,
    required VoiceSettings voice,
    required File dest,
    CancelToken? cancel,
    void Function(String message)? onLog,
  });

  Future<void> dispose();
}

class TtsException implements Exception {
  const TtsException(this.message, {this.hint});

  final String message;
  final String? hint;

  @override
  String toString() => message;
}

/// The server rejected the voice or blend: retrying cannot help.
class KokoroVoiceRejected extends TtsException {
  const KokoroVoiceRejected(String detail)
    : super(
        'The server rejected the voice.',
        hint: 'Try a plain voice such as am_onyx (no blend syntax).',
      );
}

/// The server could not be reached or kept failing; the run is resumable, nothing is lost.
class KokoroUnavailable extends TtsException {
  const KokoroUnavailable(super.message);
}
