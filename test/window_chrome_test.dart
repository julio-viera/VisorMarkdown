import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/models/app_settings.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/services/window_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  const channel = MethodChannel('window_manager');
  const appearance = MethodChannel(
    'io.github.julio_viera.VisorMarkdown/window_appearance',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appearance, (_) async => false);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appearance, null);
  });
  testWidgets(
    'window controls preserve dirty tabs, support maximize, drag and narrow layouts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings()
        ..customWindowChrome = true
        ..roundedWindowCorners = true;
      final window = WindowPreferences(settings);
      final workspace = WorkspaceController(watch: false);
      final calls = <String>[];
      var maximized = false;
      settings.persistBeforeExit = () async {
        calls.add('flushed');
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'isMaximized':
                return maximized;
              case 'isMinimized':
              case 'isFullScreen':
                return false;
              case 'getBounds':
                return {'x': 0.0, 'y': 0.0, 'width': 1200.0, 'height': 800.0};
              case 'maximize':
                maximized = true;
                window.onWindowMaximize();
              case 'unmaximize':
                maximized = false;
                window.onWindowUnmaximize();
              case 'close':
                window.onWindowClose();
            }
            return null;
          });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(
        MarkdownApp(controller: workspace, settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('window-minimize')));
      await tester.pumpAndSettle();
      expect(calls, contains('minimize'));
      await tester.tap(find.byKey(const ValueKey('window-maximize')));
      await tester.pumpAndSettle();
      expect(maximized, true);
      expect(
        tester
            .widget<ClipRRect>(find.byKey(const ValueKey('app-window-clip')))
            .borderRadius,
        BorderRadius.zero,
      );
      expect(
        tester
            .widget<DragToResizeArea>(find.byType(DragToResizeArea))
            .enableResizeEdges,
        isEmpty,
      );
      expect(find.byTooltip('Restore window'), findsOneWidget);
      final drag = find.byKey(const ValueKey('window-drag-area'));
      await tester.tap(drag);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(drag);
      await tester.pumpAndSettle();
      expect(maximized, false);
      expect(
        tester
            .widget<ClipRRect>(find.byKey(const ValueKey('app-window-clip')))
            .borderRadius,
        BorderRadius.circular(10),
      );
      window.onWindowEnterFullScreen();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ClipRRect>(find.byKey(const ValueKey('app-window-clip')))
            .borderRadius,
        BorderRadius.zero,
      );
      window.onWindowLeaveFullScreen();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DragToResizeArea>(find.byType(DragToResizeArea))
            .enableResizeEdges,
        isNull,
      );
      await tester.drag(drag, const Offset(40, 10));
      await tester.pumpAndSettle();
      expect(calls, contains('startDragging'));
      await tester.dragFrom(const Offset(350, 21), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'startDragging').length, 2);
      final closeX = tester
          .getCenter(find.byKey(const ValueKey('window-close')))
          .dx;
      for (var i = 0; i < 15; i++) {
        workspace.add();
      }
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('window-close'))).dx,
        closeX,
      );
      workspace.documents.first.editor.text = 'Unsaved background tab';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('window-close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('destroy')));
      expect(workspace.documents.first.dirty, true);
      tester.view.physicalSize = const Size(480, 700);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('window-close')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('window-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(calls, contains('destroy'));
      expect(calls.indexOf('flushed'), lessThan(calls.indexOf('destroy')));
    },
  );

  testWidgets('native title bar is hidden while keeping close interception', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final settings = AppSettings()..customWindowChrome = true;
    final window = WindowPreferences(settings);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if ([
            'isFullScreen',
            'isMaximized',
            'isMinimized',
          ].contains(call.method)) {
            return false;
          }
          return null;
        });
    addTearDown(() {
      windowManager.removeListener(window);
      settings.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await window.initialize();
    expect(settings.roundedWindowCorners, false);
    await tester.pump();
    final style = calls.firstWhere((call) => call.method == 'setTitleBarStyle');
    expect(style.arguments['titleBarStyle'], 'hidden');
    expect(style.arguments['windowButtonVisibility'], false);
    expect(
      calls
          .firstWhere((call) => call.method == 'setPreventClose')
          .arguments['isPreventClose'],
      true,
    );
  });
  testWidgets('composited Linux enables transparent rounded window corners', (
    tester,
  ) async {
    final settings = AppSettings()..customWindowChrome = true;
    final window = WindowPreferences(settings);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appearance, (_) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if ([
            'isFullScreen',
            'isMaximized',
            'isMinimized',
          ].contains(call.method)) {
            return false;
          }
          return null;
        });
    addTearDown(() {
      windowManager.removeListener(window);
      settings.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await window.initialize();
    await tester.pump();
    expect(settings.roundedWindowCorners, true);
    final background = calls.firstWhere(
      (call) => call.method == 'setBackgroundColor',
    );
    expect(background.arguments['backgroundColorA'], 0);
  });
}
