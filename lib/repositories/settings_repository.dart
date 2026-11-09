import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

/// One preferences file, independent of the working directory or installation.
class SettingsRepository {
  SettingsRepository(this.file);
  final File file;
  Future<void> _pending = Future.value();

  static Future<SettingsRepository> standard() async {
    Directory directory;
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_CONFIG_HOME'];
      final base = xdg != null && p.isAbsolute(xdg)
          ? xdg
          : p.join(Platform.environment['HOME']!, '.config');
      directory = Directory(p.join(base, 'visor-markdown'));
    } else {
      directory = await getApplicationSupportDirectory();
    }
    return SettingsRepository(File(p.join(directory.path, 'settings.json')));
  }

  Future<void> load(AppSettings settings) async {
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) settings.restore(data);
    } on FormatException catch (error) {
      debugPrint('Invalid preferences: $error');
    } on FileSystemException catch (error) {
      debugPrint('Cannot read preferences: $error');
    }
  }

  Future<void> save(AppSettings settings) {
    final contents = const JsonEncoder.withIndent('  ')
        .convert(settings.toJson());
    _pending = _pending.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.$pid.tmp');
        await temporary.writeAsString(contents, flush: true);
        await temporary.rename(file.path);
      } on FileSystemException catch (error) {
        debugPrint('Cannot save preferences: $error');
      }
    });
    return _pending;
  }

  Future<void> flush() => _pending;
}
