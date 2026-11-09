import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/l10n/strings.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/screens/workspace_screen.dart';
import 'package:visor_markdown/screens/settings_dialog.dart';

void main() {
  testWidgets(
    'all six languages fit a small screen, including large interface fonts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkspaceController(watch: false);
      await tester.pumpWidget(MarkdownApp(controller: c));
      final settings = tester
          .widget<WorkspaceScreen>(find.byType(WorkspaceScreen))
          .settings;
      for (final locale in Strings.locales) {
        settings.locale = locale;
        settings.ui.size = 32;
        settings.update();
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(
            TextField,
            Strings(locale.languageCode)['search'],
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: locale.languageCode);
      }
      settings.locale = const Locale('en');
      settings.ui.size = 14;
      settings.update();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
