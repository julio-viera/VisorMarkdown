import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/models/app_settings.dart';
import 'package:visor_markdown/screens/workspace_screen.dart';
import 'package:visor_markdown/themes/app_theme.dart';

void main() {
  test('all palettes support light, dark and high-contrast schemes', () {
    final settings = AppSettings();
    addTearDown(settings.dispose);
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    final primaries = <Color>{};
    for (final palette in ThemePalette.values) {
      settings.palette = palette;
      for (final brightness in Brightness.values) {
        for (final high in [false, true]) {
          settings.highContrast = high;
          final theme = appTheme(brightness, settings);
          expect(theme.brightness, brightness);
          final chrome = DocumentChromeColors(theme.colorScheme);
          if (palette == ThemePalette.logo) {
            final scheme = theme.colorScheme;
            expect(
              contrast(scheme.secondary, scheme.onSecondary),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrast(scheme.secondaryContainer, scheme.onSecondaryContainer),
              greaterThanOrEqualTo(4.5),
            );
            for (final surface in [
              scheme.surfaceContainer,
              scheme.surfaceContainerHighest,
            ]) {
              expect(
                contrast(scheme.onSurface, surface),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
          if (palette == ThemePalette.defaults) {
            for (final color in [
              chrome.strip,
              chrome.active,
              chrome.inactive,
              theme.colorScheme.primary,
            ]) {
              expect(color.r, color.g);
              expect(color.g, color.b);
            }
          }
          expect(
            contrast(theme.colorScheme.primary, chrome.active),
            greaterThanOrEqualTo(4.5),
            reason: '${palette.name} $brightness active tab',
          );
          expect(
            contrast(theme.colorScheme.onSurface, chrome.inactive),
            greaterThan(7),
          );
          expect(
            chrome.active.computeLuminance(),
            greaterThan(chrome.inactive.computeLuminance()),
          );
          expect(
            chrome.inactive.computeLuminance(),
            greaterThan(chrome.strip.computeLuminance()),
          );
          expect(
            contrast(theme.colorScheme.onSurface, theme.colorScheme.surface),
            greaterThan(7),
          );
          if (high) {
            expect(
              contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
              greaterThan(7),
            );
          }
        }
      }
      settings.highContrast = false;
      primaries.add(appTheme(Brightness.light, settings).colorScheme.primary);
    }
    expect(primaries.length, ThemePalette.values.length);
  });

  testWidgets(
    'settings change the app palette and contrast, and toolbar has a subtle separator',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkspaceController(watch: false);
      await tester.pumpWidget(MarkdownApp(controller: c));
      await tester.pumpAndSettle();
      final settings = tester
          .widget<WorkspaceScreen>(find.byType(WorkspaceScreen))
          .settings;
      expect(settings.palette, ThemePalette.logo);
      final toolbar = find.byKey(const ValueKey('document-toolbar'));
      final decoration =
          tester.widget<DecoratedBox>(toolbar).decoration as BoxDecoration;
      expect((decoration.border! as Border).bottom.width, .5);
      expect(decoration.boxShadow, isNull);
      expect(tester.getSize(toolbar).width, 1200);
      await tester.tap(find.byKey(const ValueKey('settings-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-palette')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ocean').last);
      await tester.pumpAndSettle();
      expect(settings.palette, ThemePalette.ocean);
      await tester.tap(find.byKey(const ValueKey('theme-high-contrast')));
      await tester.pumpAndSettle();
      expect(settings.highContrast, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
