import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/app_settings.dart';

class WindowPreferences with WindowListener {
  WindowPreferences(this.settings);
  final AppSettings settings;
  Timer? _resize;
  bool _closing = false;
  static bool get supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<void> initialize() async {
    if (Platform.isLinux && settings.customWindowChrome) {
      try {
        settings.roundedWindowCorners =
            await const MethodChannel(
                  'io.github.julio_viera.VisorMarkdown/window_appearance',
                )
                .invokeMethod<bool>('supportsRoundedCorners')
                .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
            false;
      } on MissingPluginException {
        settings.roundedWindowCorners = false;
      } on PlatformException {
        settings.roundedWindowCorners = false;
      }
    }
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: settings.windowSize,
        minimumSize: const Size(480, 320),
        title: 'Visor Markdown',
        backgroundColor: settings.roundedWindowCorners
            ? const Color(0x00000000)
            : null,
        titleBarStyle: settings.customWindowChrome
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
        windowButtonVisibility: !settings.customWindowChrome,
      ),
      () async {
        if (settings.windowMaximized) await windowManager.maximize();
        await windowManager.show();
      },
    );
    windowManager.addListener(this);
  }

  Future<void> capture() async {
    final maximized = await windowManager.isMaximized();
    final minimized = await windowManager.isMinimized();
    final fullscreen = await windowManager.isFullScreen();
    if (!minimized && !fullscreen) {
      settings.windowMaximized = maximized;
      if (!maximized) settings.windowSize = await windowManager.getSize();
      settings.update();
    }
  }

  @override
  void onWindowClose() async {
    if (_closing || settings.confirmWindowClose == null) return;
    _closing = true;
    try {
      if (await settings.confirmWindowClose!()) {
        _resize?.cancel();
        await capture();
        await settings.persistBeforeExit?.call();
        await windowManager.destroy();
      }
    } finally {
      _closing = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    settings.windowFullScreen = true;
    settings.update();
  }

  @override
  void onWindowLeaveFullScreen() {
    settings.windowFullScreen = false;
    settings.update();
  }

  @override
  void onWindowResize() {
    _resize?.cancel();
    _resize = Timer(const Duration(milliseconds: 250), capture);
  }

  @override
  void onWindowMaximize() {
    settings.windowMaximized = true;
    settings.update();
  }

  @override
  void onWindowUnmaximize() {
    settings.windowMaximized = false;
    settings.update();
  }
}
