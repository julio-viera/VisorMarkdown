import 'package:flutter/material.dart';

import '../models/app_settings.dart';

ThemeData appTheme(Brightness brightness, AppSettings settings) {
  var scheme = ColorScheme.fromSeed(
    seedColor: settings.palette.seed,
    dynamicSchemeVariant: settings.palette == ThemePalette.defaults
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
    brightness: brightness,
    contrastLevel: settings.highContrast ? 1 : 0,
  );
  if (settings.palette == ThemePalette.logo) {
    final dark = brightness == Brightness.dark;
    final turquoise = ColorScheme.fromSeed(
      seedColor: const Color(0xff65dfc8),
      brightness: brightness,
      contrastLevel: settings.highContrast ? 1 : 0,
    );
    scheme = scheme.copyWith(
      secondary: turquoise.primary,
      onSecondary: turquoise.onPrimary,
      secondaryContainer: turquoise.primaryContainer,
      onSecondaryContainer: turquoise.onPrimaryContainer,
      surface: dark ? const Color(0xff181e34) : const Color(0xfffaf9ff),
      surfaceContainerLowest: dark ? const Color(0xff13182b) : Colors.white,
      surfaceContainerLow: dark
          ? const Color(0xff1c233a)
          : const Color(0xfff4f2fc),
      surfaceContainer: dark
          ? const Color(0xff212942)
          : const Color(0xffeeecf8),
      surfaceContainerHigh: dark
          ? const Color(0xff272f4b)
          : const Color(0xffe9e6f4),
      surfaceContainerHighest: dark
          ? const Color(0xff2e3756)
          : const Color(0xffe3e0ef),
    );
  }
  if (settings.palette == ThemePalette.sepia) {
    scheme = scheme.copyWith(
      surface: brightness == Brightness.light
          ? const Color(0xfffbf6ea)
          : const Color(0xff211d16),
      surfaceContainerLowest: brightness == Brightness.light
          ? const Color(0xfffffbf2)
          : const Color(0xff19150f),
      surfaceContainerLow: brightness == Brightness.light
          ? const Color(0xfff5edde)
          : const Color(0xff282219),
      surfaceContainer: brightness == Brightness.light
          ? const Color(0xffeee4d2)
          : const Color(0xff30291e),
    );
  }
  final theme = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = theme.typography.englishLike.merge(theme.textTheme);
  TextStyle? style(TextStyle? base) => base?.copyWith(
    fontSize: (base.fontSize ?? 14) * settings.ui.size / 14,
    fontFamily: settings.ui.family,
    fontWeight: settings.ui.bold ? FontWeight.bold : base.fontWeight,
    fontStyle: settings.ui.italic ? FontStyle.italic : FontStyle.normal,
  );
  return theme.copyWith(
    textTheme: TextTheme(
      displayLarge: style(text.displayLarge),
      displayMedium: style(text.displayMedium),
      displaySmall: style(text.displaySmall),
      headlineLarge: style(text.headlineLarge),
      headlineMedium: style(text.headlineMedium),
      headlineSmall: style(text.headlineSmall),
      titleLarge: style(text.titleLarge),
      titleMedium: style(text.titleMedium),
      titleSmall: style(text.titleSmall),
      bodyLarge: style(text.bodyLarge),
      bodyMedium: style(text.bodyMedium),
      bodySmall: style(text.bodySmall),
      labelLarge: style(text.labelLarge),
      labelMedium: style(text.labelMedium),
      labelSmall: style(text.labelSmall),
    ),
  );
}

/// Neutral editor surfaces keep document text readable in every palette.
class EditorColors {
  const EditorColors(Brightness brightness)
    : dark = brightness == Brightness.dark;
  final bool dark;
  Color get background => dark ? const Color(0xff101216) : Colors.white;
  Color get foreground =>
      dark ? const Color(0xfff5f7fa) : const Color(0xff141619);
  Color get gutter => dark ? const Color(0xff191d23) : const Color(0xfff1f3f5);
  Color get lineNumber =>
      dark ? const Color(0xffbdc5d0) : const Color(0xff46505c);
}

/// Keep the active tab and toolbar continuous, above a darker tab backdrop.
class DocumentChromeColors {
  const DocumentChromeColors(this.scheme);
  final ColorScheme scheme;
  bool get dark => scheme.brightness == Brightness.dark;
  // Derive hue and saturation from the chosen palette while controlling
  // lightness separately so tabs remain distinct in both brightness modes.
  Color tone(double lightness, double saturation) {
    final primary = HSLColor.fromColor(scheme.primary);
    return primary
        .withSaturation(primary.saturation * saturation)
        .withLightness(lightness)
        .toColor();
  }

  bool get neutral => HSLColor.fromColor(scheme.primary).saturation < .01;
  Color get strip =>
      tone(dark ? (neutral ? .10 : .12) : (neutral ? .68 : .72), .8);
  Color get active =>
      tone(dark ? (neutral ? .24 : .27) : (neutral ? .94 : .96), .35);
  Color get inactive =>
      tone(dark ? (neutral ? .18 : .20) : (neutral ? .84 : .86), .5);
}
