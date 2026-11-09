import 'package:flutter/material.dart';

class FontSettings {
  FontSettings({
    this.size = 14,
    this.family = 'sans-serif',
    this.bold = false,
    this.italic = false,
  });
  double size;
  String family;
  bool bold;
  bool italic;
  TextStyle get style => TextStyle(
    fontSize: size,
    fontFamily: family,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  );
}

enum ThemePalette {
  logo(Color(0xffb09aff)),
  defaults(Color(0xff616161)),
  ocean(Color(0xff2563eb)),
  forest(Color(0xff39754a)),
  violet(Color(0xff7950c8)),
  rose(Color(0xffb84d73)),
  amber(Color(0xffa56b14)),
  slate(Color(0xff526276)),
  sepia(Color(0xff876440));

  const ThemePalette(this.seed);
  final Color seed;
  String get labelKey => 'palette${name[0].toUpperCase()}${name.substring(1)}';
}

class AppSettings extends ChangeNotifier {
  ThemeMode theme = ThemeMode.system;
  ThemePalette palette = ThemePalette.logo;
  bool highContrast = false;
  Locale? locale;
  final ui = FontSettings();
  final editor = FontSettings(family: 'monospace');
  final preview = FontSettings(size: 16);
  String? lastOpenDirectory;
  String? lastSaveDirectory;
  Size windowSize = const Size(1280, 720);
  bool windowMaximized = false;
  // Runtime window capabilities, not user preferences.
  bool customWindowChrome = false;
  bool desktopFileEvents = false;
  bool roundedWindowCorners = false;
  bool windowFullScreen = false;
  Future<void> Function()? persistBeforeExit;
  Future<bool> Function()? confirmWindowClose;

  Map<String, dynamic> toJson() => {
    'version': 2,
    'theme': theme.name,
    'palette': palette.name,
    'highContrast': highContrast,
    'locale': locale?.languageCode,
    for (final entry in {
      'ui': ui,
      'editor': editor,
      'preview': preview,
    }.entries)
      entry.key: {
        'size': entry.value.size,
        'family': entry.value.family,
        'bold': entry.value.bold,
        'italic': entry.value.italic,
      },
    'lastOpenDirectory': lastOpenDirectory,
    'lastSaveDirectory': lastSaveDirectory,
    'window': {
      'width': windowSize.width,
      'height': windowSize.height,
      'maximized': windowMaximized,
    },
  };

  void restore(Map<String, dynamic> data) {
    for (final value in ThemeMode.values) {
      if (data['theme'] == value.name) theme = value;
    }
    for (final value in ThemePalette.values) {
      if (data['palette'] == value.name) palette = value;
    }
    // Migrate the removed palette regardless of the preferences version.
    if (data['palette'] == 'teal') {
      palette = ThemePalette.defaults;
    }
    if (data['highContrast'] is bool) highContrast = data['highContrast'];
    if (['en', 'es', 'pt', 'de', 'fr', 'it'].contains(data['locale'])) {
      locale = Locale(data['locale']);
    }
    for (final entry in {
      'ui': ui,
      'editor': editor,
      'preview': preview,
    }.entries) {
      final font = data[entry.key];
      if (font is! Map) continue;
      final size = font['size'];
      if (size is num && size.isFinite && size >= 10 && size <= 32) {
        entry.value.size = size.toDouble();
      }
      if (['sans-serif', 'serif', 'monospace'].contains(font['family'])) {
        entry.value.family = font['family'];
      }
      if (font['bold'] is bool) entry.value.bold = font['bold'];
      if (font['italic'] is bool) entry.value.italic = font['italic'];
    }
    if (data['lastOpenDirectory'] is String) {
      lastOpenDirectory = data['lastOpenDirectory'];
    }
    if (data['lastSaveDirectory'] is String) {
      lastSaveDirectory = data['lastSaveDirectory'];
    }
    final window = data['window'];
    if (window is Map) {
      final width = window['width'], height = window['height'];
      if (width is num &&
          height is num &&
          width.isFinite &&
          height.isFinite &&
          width >= 480 &&
          height >= 320 &&
          width <= 16384 &&
          height <= 16384) {
        windowSize = Size(width.toDouble(), height.toDouble());
      }
      if (window['maximized'] is bool) windowMaximized = window['maximized'];
    }
  }

  void update() => notifyListeners();
}
