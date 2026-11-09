import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/models/app_settings.dart';
import 'package:visor_markdown/services/window_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  var maximized = false;
  var minimized = false;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    maximized = minimized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'isMinimized':
              return minimized;
            case 'isFullScreen':
              return false;
            case 'getBounds':
              return {'x': 0.0, 'y': 0.0, 'width': 940.0, 'height': 650.0};
            default:
              return null;
          }
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('normal size survives maximizing and minimizing', () async {
    final settings = AppSettings();
    final window = WindowPreferences(settings);
    await window.capture();
    expect(settings.windowSize, const Size(940, 650));
    maximized = true;
    await window.capture();
    expect(settings.windowMaximized, true);
    expect(settings.windowSize, const Size(940, 650));
    minimized = true;
    maximized = false;
    await window.capture();
    expect(settings.windowMaximized, true);
    expect(settings.windowSize, const Size(940, 650));
  });

  test(
    'native close respects cancellation and flushes before destroying',
    () async {
      final settings = AppSettings();
      final window = WindowPreferences(settings);
      var allow = false;
      settings.confirmWindowClose = () async => allow;
      settings.persistBeforeExit = () async {
        calls.add(const MethodCall('flushed'));
      };
      window.onWindowClose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.method == 'destroy'), isEmpty);
      allow = true;
      window.onWindowClose();
      await Future<void>.delayed(Duration.zero);
      final names = calls.map((call) => call.method).toList();
      expect(names, contains('destroy'));
      expect(names.indexOf('flushed'), lessThan(names.indexOf('destroy')));
    },
  );
}
