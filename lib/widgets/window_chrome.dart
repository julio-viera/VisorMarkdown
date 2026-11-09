import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/strings.dart';
import '../models/app_settings.dart';

Future<void> toggleWindowMaximized() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Use only over free title-bar space, keeping tab scrolling and buttons native.
class WindowDragRegion extends StatelessWidget {
  const WindowDragRegion({
    super.key,
    required this.enabled,
    required this.child,
  });
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) => !enabled
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: toggleWindowMaximized,
          child: child,
        );
}

class WindowChromeControls extends StatelessWidget {
  const WindowChromeControls({
    super.key,
    required this.settings,
    required this.strings,
  });
  final AppSettings settings;
  final Strings strings;

  Widget button(
    String key,
    String label,
    IconData icon,
    VoidCallback action, {
    bool close = false,
  }) => IconButton(
    key: ValueKey(key),
    tooltip: label,
    onPressed: action,
    icon: Icon(icon, size: 17),
    style: ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: const WidgetStatePropertyAll(Size(36, 42)),
      maximumSize: const WidgetStatePropertyAll(Size(36, 42)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      backgroundColor: close
          ? WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? const Color(0xffb3261e)
                  : null,
            )
          : null,
      foregroundColor: close
          ? WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? Colors.white
                  : null,
            )
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      button(
        'window-minimize',
        strings['minimizeWindow'],
        Icons.remove,
        () => windowManager.minimize(),
      ),
      button(
        'window-maximize',
        strings[settings.windowMaximized ? 'restoreWindow' : 'maximizeWindow'],
        settings.windowMaximized ? Icons.filter_none : Icons.crop_square,
        toggleWindowMaximized,
      ),
      // Native close is intercepted by WindowPreferences, including unsaved tabs.
      button(
        'window-close',
        strings['closeWindow'],
        Icons.close,
        () => windowManager.close(),
        close: true,
      ),
    ],
  );
}
