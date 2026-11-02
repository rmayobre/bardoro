// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const sampleRate = 24000;

/// Reads `name.npy` entries of an npz: float32, C order. Returns the flattened (rows x 256) pack.
Map<String, Float32List> loadVoices(String npzPath, List<String> names) {
  final archive = ZipDecoder().decodeBytes(File(npzPath).readAsBytesSync());
  final out = <String, Float32List>{};
  for (final n in names) {
    final file = archive.findFile('$n.npy');
    if (file == null) throw StateError('$n.npy not in $npzPath');
    final bytes = Uint8List.fromList(file.readBytes()!);
    if (bytes[0] != 0x93 ||
        String.fromCharCodes(bytes.sublist(1, 6)) != 'NUMPY') {
      throw StateError('not an .npy');
    }
    final major = bytes[6];
    final headerLen = major == 1
        ? bytes[8] | bytes[9] << 8
        : ByteData.sublistView(bytes, 8, 12).getUint32(0, Endian.little);
    final start = (major == 1 ? 10 : 12) + headerLen;
    final header = String.fromCharCodes(
      bytes.sublist(major == 1 ? 10 : 12, start),
    );
    if (!header.contains("'<f4'") || header.contains('True')) {
      throw StateError('unexpected .npy header: $header');
    }
    out[n] = Float32List.fromList(Float32List.sublistView(bytes, start));
  }
  return out;
}

double peak(Float32List a) => a.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

/// Minimal WAV reader: PCM16 or float32, mono.
Float32List readWav(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var pos = 12;
  int? format, bits;
  while (pos + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(pos, pos + 4));
    final size = d.getUint32(pos + 4, Endian.little);
    if (id == 'fmt ') {
      format = d.getUint16(pos + 8, Endian.little);
      bits = d.getUint16(pos + 22, Endian.little);
    } else if (id == 'data') {
      final data = Uint8List.sublistView(b, pos + 8, pos + 8 + size);
      final dd = ByteData.sublistView(data);
      if (format == 3 && bits == 32) {
        return Float32List.fromList([
          for (var i = 0; i < size ~/ 4; i++)
            dd.getFloat32(i * 4, Endian.little),
        ]);
      }
      if (format == 1 && bits == 16) {
        return Float32List.fromList([
          for (var i = 0; i < size ~/ 2; i++)
            dd.getInt16(i * 2, Endian.little) / 32768,
        ]);
      }
      throw StateError('Unsupported WAV format $format/$bits in $path');
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('No data chunk in $path');
}

void writeWav(String path, Float32List samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(
      i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  final header = ByteData(44)
    ..setUint32(4, 36 + data.lengthInBytes, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, data.lengthInBytes, Endian.little);
  final bytes = BytesBuilder()..add(header.buffer.asUint8List());
  bytes.add(data.buffer.asUint8List());
  final b = bytes.toBytes();
  b.setRange(0, 4, 'RIFF'.codeUnits);
  b.setRange(8, 16, 'WAVEfmt '.codeUnits);
  b.setRange(36, 40, 'data'.codeUnits);
  File(path).writeAsBytesSync(b);
}
