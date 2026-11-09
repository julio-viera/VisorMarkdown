import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Bound input before parsing or allocating a document's widget tree.
class DocumentLimits {
  static const maxBytes = 2 * 1024 * 1024;
  static const maxLines = 20000;
  static const message = 'Document limit: 2 MiB and 20,000 lines.';

  static String decode(List<int> bytes) {
    if (bytes.length > maxBytes) throw const FormatException(message);
    final text = utf8.decode(bytes);
    validate(text);
    return text;
  }

  static void validate(String text) {
    if (text.length > maxBytes ||
        (text.length > maxBytes ~/ 3 && utf8.encode(text).length > maxBytes)) {
      throw const FormatException(message);
    }
    var lines = 1;
    for (var i = 0; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      if (char == 13 ||
          (char == 10 && (i == 0 || text.codeUnitAt(i - 1) != 13))) {
        if (++lines > maxLines) throw const FormatException(message);
      }
    }
  }

  static Future<Uint8List> readBytes(File file, int limit) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Not a regular file', file.path);
    }
    if (stat.size > limit) {
      throw const FormatException('File too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('File too large');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<String> read(File file) async =>
      decode(await readBytes(file, maxBytes));
}
