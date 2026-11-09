import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/document_limits.dart';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as selector;

class OpenedFile {
  OpenedFile(this.name, this.text, this.path, {this.sourceId});
  final String? sourceId;
  final String name;
  final String text;
  final String? path;
}

class DocumentRepository {
  DocumentRepository({this.settings});
  final AppSettings? settings;
  String? directory(String? value) =>
      value != null && Directory(value).existsSync() ? value : null;
  void remember(String path, {bool saving = false}) {
    if (settings == null) return;
    if (saving) {
      settings!.lastSaveDirectory = p.dirname(path);
    } else {
      settings!.lastOpenDirectory = p.dirname(path);
    }
    settings!.update();
  }

  bool get mobile => Platform.isAndroid || Platform.isIOS;
  Future<List<OpenedFile>> pick() async {
    if (!mobile) {
      final file = await selector.openFile(
        initialDirectory: directory(settings?.lastOpenDirectory),
        acceptedTypeGroups: const [
          selector.XTypeGroup(
            label: 'Markdown',
            extensions: ['md', 'markdown', 'mdown', 'mkd', 'txt'],
          ),
        ],
      );
      if (file == null) return [];
      final text = await read(file.path);
      remember(file.path);
      return [OpenedFile(file.name, text, file.path)];
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'mdown', 'mkd', 'txt'],
      withData: false,
    );
    if (result == null) return [];
    final files = <OpenedFile>[];
    for (final file in result.files) {
      if (file.size > DocumentLimits.maxBytes) {
        throw const FormatException(DocumentLimits.message);
      }
      final text = file.bytes != null
          ? DocumentLimits.decode(file.bytes!)
          : await read(file.path!);
      files.add(OpenedFile(file.name, text, null));
    }
    return files;
  }

  Future<String> canonicalPath(String path) async {
    final uri = Uri.tryParse(path);
    final file = File(uri?.scheme == 'file' ? uri!.toFilePath() : path);
    try {
      return p.normalize(await file.resolveSymbolicLinks());
    } on FileSystemException {
      return p.normalize(file.absolute.path);
    }
  }

  bool samePath(String first, String second) => Platform.isWindows
      ? first.toLowerCase() == second.toLowerCase()
      : first == second;

  Future<String> read(String path) => DocumentLimits.read(File(path));
  Future<String?> stamp(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return '${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';
  }

  Future<void> write(String path, String text) =>
      _replaceFile(path, (file) => file.writeAsString(text, flush: true));

  Future<void> _replaceFile(
    String path,
    Future<File> Function(File) writeTemporary,
  ) async {
    var destination = File(path).absolute;
    final type = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      destination = File(await destination.resolveSymbolicLinks());
    }
    final stat = await destination.stat();
    if (stat.type != FileSystemEntityType.file &&
        stat.type != FileSystemEntityType.notFound) {
      throw FileSystemException('Not a regular file', path);
    }

    final preserveMode =
        (Platform.isLinux || Platform.isMacOS) &&
        stat.type == FileSystemEntityType.file;
    if (preserveMode && (stat.mode & 0x92) == 0) {
      throw FileSystemException('File is read-only', path);
    }
    final staging = await destination.parent.createTemp('.visor-markdown-');
    try {
      final temporary = File(p.join(staging.path, 'document'));
      await writeTemporary(temporary);
      if (preserveMode) {
        final mode = (stat.mode & 0x1ff).toRadixString(8);
        final result = await Process.run('chmod', [mode, temporary.path]);
        if (result.exitCode != 0) {
          throw FileSystemException('Cannot preserve file permissions', path);
        }
      }
      await temporary.rename(destination.path);
    } finally {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // Cleanup must not hide a write error or report a committed save as failed.
      }
    }
  }

  Future<String?> saveBytesAs(
    String name,
    Uint8List bytes,
    String extension,
  ) async {
    if (mobile) {
      return FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
    }
    final location = await selector.getSaveLocation(
      initialDirectory: directory(
        settings?.lastSaveDirectory ?? settings?.lastOpenDirectory,
      ),
      suggestedName: name,
      acceptedTypeGroups: [
        selector.XTypeGroup(
          label: extension.toUpperCase(),
          extensions: [extension],
        ),
      ],
    );
    if (location == null) return null;
    await _replaceFile(
      location.path,
      (file) => file.writeAsBytes(bytes, flush: true),
    );
    remember(location.path, saving: true);
    return location.path;
  }

  Future<String?> saveAs(String name, String text, String extension) async {
    if (mobile) {
      return FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
    }
    final location = await selector.getSaveLocation(
      initialDirectory: directory(
        settings?.lastSaveDirectory ?? settings?.lastOpenDirectory,
      ),
      suggestedName: name,
      acceptedTypeGroups: [
        selector.XTypeGroup(
          label: extension.toUpperCase(),
          extensions: [extension],
        ),
      ],
    );
    if (location == null) return null;
    await write(location.path, text);
    remember(location.path, saving: true);
    return location.path;
  }
}
