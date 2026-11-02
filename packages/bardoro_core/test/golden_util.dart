// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

/// Fixtures written by test/golden/make_golden.py from the Python reference tools.
String goldenPath(String name) => 'test/golden/$name';

Object? readGoldenJson(String name) =>
    jsonDecode(File(goldenPath(name)).readAsStringSync());

Map<String, dynamic> readUnits() =>
    readGoldenJson('units.json') as Map<String, dynamic>;
