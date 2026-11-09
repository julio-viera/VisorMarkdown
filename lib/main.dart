import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_info.dart';
import 'repositories/settings_repository.dart';
import 'services/window_preferences.dart';
import 'controllers/workspace_controller.dart';
import 'l10n/strings.dart';
import 'models/app_settings.dart';
import 'screens/workspace_screen.dart';
import 'themes/app_theme.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInfo.load();
  final settings = AppSettings()
    ..customWindowChrome = Platform.isLinux || Platform.isWindows
    ..desktopFileEvents = Platform.isLinux || Platform.isWindows;
  final repository = await SettingsRepository.standard();
  await repository.load(settings);
  settings.addListener(() {
    repository.save(settings);
  });
  WindowPreferences? window;
  if (WindowPreferences.supported) {
    window = WindowPreferences(settings);
    await window.initialize();
  }
  settings.persistBeforeExit = () async {
    await window?.capture();
    await repository.flush();
  };
  runApp(MarkdownApp(arguments: arguments, settings: settings));
}

class MarkdownApp extends StatefulWidget {
  const MarkdownApp({
    super.key,
    this.arguments = const [],
    this.controller,
    this.settings,
  });
  final List<String> arguments;
  final WorkspaceController? controller;
  final AppSettings? settings;
  @override
  State<MarkdownApp> createState() => _MarkdownAppState();
}

class _MarkdownAppState extends State<MarkdownApp> {
  late final settings = widget.settings ?? AppSettings();
  @override
  void dispose() {
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => settings.customWindowChrome
          ? DragToResizeArea(
              resizeEdgeSize: 4,
              enableResizeEdges:
                  settings.windowMaximized || settings.windowFullScreen
                  ? const []
                  : null,
              child: ClipRRect(
                key: const ValueKey('app-window-clip'),
                borderRadius: BorderRadius.circular(
                  settings.roundedWindowCorners &&
                          !settings.windowMaximized &&
                          !settings.windowFullScreen
                      ? 10
                      : 0,
                ),
                child: child!,
              ),
            )
          : child!,
      locale: settings.locale,
      supportedLocales: Strings.locales,
      localeListResolutionCallback: (locales, supported) {
        for (final locale in locales ?? <Locale>[]) {
          for (final candidate in supported) {
            if (candidate.languageCode == locale.languageCode) return candidate;
          }
        }
        return const Locale('en');
      },
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(Brightness.light, settings),
      darkTheme: appTheme(Brightness.dark, settings),
      themeMode: settings.theme,
      home: WorkspaceScreen(
        settings: settings,
        arguments: widget.arguments,
        controller: widget.controller,
      ),
    ),
  );
}
