// SPDX-License-Identifier: GPL-3.0-or-later

/// Reads CSV the way Python's `csv.reader` does with its default (excel) dialect: `"` quotes a field only at
/// its start, `""` inside quotes is a quote, quoted fields may hold newlines, `\r`, `\n` and `\r\n` end a row,
/// and an empty line is an empty row (`[]`).
List<List<String>> parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var atFieldStart =
      true; // nothing consumed yet in this field: only here can `"` open a quote
  var rowStarted = false; // saw any character of the current row
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
    atFieldStart = true;
  }

  void endRow() {
    if (rowStarted) endField();
    rows.add(row);
    row = <String>[];
    rowStarted = false;
    atFieldStart = true;
  }

  while (i < input.length) {
    final c = input[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && atFieldStart) {
      inQuotes = true;
      atFieldStart = false;
      rowStarted = true;
    } else if (c == ',') {
      endField();
      rowStarted = true;
    } else if (c == '\n' || c == '\r') {
      endRow();
      if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
    } else {
      field.write(c);
      atFieldStart = false;
      rowStarted = true;
    }
    i++;
  }
  if (rowStarted) endRow();
  return rows;
}

/// One row as `csv.writer(lineterminator="\n")` writes it (QUOTE_MINIMAL).
String formatCsvRow(List<String> fields) {
  if (fields.length == 1 && fields[0].isEmpty) return '""\n';
  final out = fields.map((f) {
    final needsQuotes =
        f.contains(',') ||
        f.contains('"') ||
        f.contains('\n') ||
        f.contains('\r');
    return needsQuotes ? '"${f.replaceAll('"', '""')}"' : f;
  });
  return '${out.join(',')}\n';
}
