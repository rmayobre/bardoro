// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spike_s1_onnx/spike_io.dart';

/// An .npy v1.0 file exactly as numpy writes it: magic, version, u16 header length, header padded with spaces.
Uint8List npy(Float32List data, List<int> shape) {
  var header =
      "{'descr': '<f4', 'fortran_order': False, 'shape': (${shape.join(', ')}), }";
  while ((10 + header.length + 1) % 64 != 0) {
    header += ' ';
  }
  header += '\n';
  final b = BytesBuilder()
    ..add([
      0x93,
      ...'NUMPY'.codeUnits,
      1,
      0,
      header.length & 0xff,
      header.length >> 8,
    ])
    ..add(utf8.encode(header))
    ..add(data.buffer.asUint8List());
  return b.toBytes();
}

void main() {
  test('writeWav then readWav round-trips within 16-bit precision', () {
    final dir = Directory.systemTemp.createTempSync('spike_io');
    addTearDown(() => dir.deleteSync(recursive: true));
    final samples = Float32List.fromList([
      for (var i = 0; i < 2400; i++) 0.5 * (i % 100 - 50) / 50,
    ]);
    writeWav('${dir.path}/a.wav', samples);
    final back = readWav('${dir.path}/a.wav');
    expect(back.length, samples.length);
    for (var i = 0; i < samples.length; i++) {
      expect(back[i], closeTo(samples[i], 1 / 32767 + 1e-6));
    }
    expect(peak(back), closeTo(0.5, 1e-3));
  });

  test('readWav reads float32 WAV files', () {
    final dir = Directory.systemTemp.createTempSync('spike_io');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = Float32List.fromList([0.25, -0.5, 1.0]);
    final b = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(
        (ByteData(
          4,
        )..setUint32(0, 36 + 12, Endian.little)).buffer.asUint8List(),
      )
      ..add(ascii.encode('WAVEfmt '))
      ..add(
        (ByteData(20)
              ..setUint32(0, 16, Endian.little)
              ..setUint16(4, 3, Endian.little)
              ..setUint16(6, 1, Endian.little)
              ..setUint32(8, 24000, Endian.little)
              ..setUint32(12, 96000, Endian.little)
              ..setUint16(16, 4, Endian.little)
              ..setUint16(18, 32, Endian.little))
            .buffer
            .asUint8List(),
      )
      ..add(ascii.encode('data'))
      ..add((ByteData(4)..setUint32(0, 12, Endian.little)).buffer.asUint8List())
      ..add(f.buffer.asUint8List());
    File('${dir.path}/f.wav').writeAsBytesSync(b.toBytes());
    expect(readWav('${dir.path}/f.wav'), f);
  });

  test('loadVoices reads a (510, 1, 256) pack from an npz', () {
    final dir = Directory.systemTemp.createTempSync('spike_io');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pack = Float32List.fromList([
      for (var i = 0; i < 510 * 256; i++) i.toDouble(),
    ]);
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('am_onyx.npy', npy(pack, [510, 1, 256])));
    File('${dir.path}/v.bin').writeAsBytesSync(ZipEncoder().encode(archive));
    final voices = loadVoices('${dir.path}/v.bin', ['am_onyx']);
    expect(voices['am_onyx']!.length, 510 * 256);
    expect(voices['am_onyx']![256 * 36 + 3], 256 * 36 + 3); // row 36, column 3
  });
}
