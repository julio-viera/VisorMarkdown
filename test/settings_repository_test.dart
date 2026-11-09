import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/models/app_settings.dart';
import 'package:visor_markdown/repositories/settings_repository.dart';

void main() {
  test(
    'preferences survive restart, including fonts, window and folders',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'visor-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = SettingsRepository(
        File('${directory.path}/config/settings.json'),
      );
      final original = AppSettings()
        ..theme = ThemeMode.dark
        ..palette = ThemePalette.sepia
        ..highContrast = true
        ..locale = const Locale('es')
        ..windowSize = const Size(937, 643)
        ..windowMaximized = true
        ..lastOpenDirectory = '/tmp/Documentos con espacios/ñ'
        ..lastSaveDirectory = '/tmp/exportaciones';
      original.editor.size = 23;
      original.editor.bold = true;
      original.preview.italic = true;
      original.ui.family = 'serif';
      await repository.save(original);
      final restored = AppSettings();
      await SettingsRepository(repository.file).load(restored);
      expect(restored.toJson(), original.toJson());
      // Rapid changes must not allow an older write to replace the final value.
      for (var i = 0; i < 8; i++) {
        original.windowSize = Size(800 + i.toDouble(), 600);
        repository.save(original);
      }
      await repository.flush();
      await repository.load(restored);
      expect(restored.windowSize, const Size(807, 600));
    },
  );

  test(
    'missing, malformed and invalid preferences retain usable defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'visor-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = SettingsRepository(
        File('${directory.path}/settings.json'),
      );
      final settings = AppSettings();
      await repository.load(settings);
      await repository.file.writeAsString('{broken');
      await repository.load(settings);
      settings.restore({
        'theme': 'unknown',
        'locale': 'unknown',
        'editor': {'size': -5, 'family': 'missing', 'bold': 'true'},
        'window': {'width': -10, 'height': 0},
      });
      expect(settings.palette, ThemePalette.logo);
      settings.restore({'palette': 'defaults'});
      expect(settings.palette, ThemePalette.defaults);
      settings.restore({'version': 1, 'palette': 'teal'});
      expect(settings.palette, ThemePalette.defaults);
      settings.restore({'version': 2, 'palette': 'teal'});
      expect(settings.palette, ThemePalette.defaults);
      settings.restore({'version': 1, 'palette': 'ocean'});
      expect(settings.palette, ThemePalette.ocean);
      expect(settings.theme, ThemeMode.system);
      expect(settings.locale, null);
      expect(settings.editor.size, 14);
      expect(settings.editor.family, 'monospace');
      expect(settings.editor.bold, false);
      expect(settings.windowSize, const Size(1280, 720));
    },
  );
}
