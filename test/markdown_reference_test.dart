import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/screens/markdown_reference_dialog.dart';

void main() {
  for (final width in [380.0, 1200.0]) {
    testWidgets('Markdown reference follows the dialect at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = WorkspaceController(watch: false);
      workspace.active.dialect = MarkdownDialect.original;
      await tester.pumpWidget(MarkdownApp(controller: workspace));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      });

      final button = find.byKey(const ValueKey('markdown-reference-action'));
      final preview = width >= 800
          ? find.byKey(const ValueKey('toggle-preview-action'))
          : find.byType(SegmentedButton<bool>);
      expect(
        tester.getCenter(button).dy,
        closeTo(tester.getCenter(preview).dy, 8),
      );
      expect(
        tester.getCenter(button).dx,
        greaterThan(tester.getCenter(preview).dx),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      final dialog = find.byType(MarkdownReferenceDialog);
      expect(dialog, findsOneWidget);
      final selector = find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('markdown-standard')),
      );
      final examples = find.descendant(
        of: dialog,
        matching: find.byType(ListView),
      );
      expect(find.text('Headings'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.byType(MarkdownBody)),
        findsWidgets,
      );
      expect(
        tester.widget<ListView>(examples).childrenDelegate.estimatedChildCount,
        15,
      );

      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GitHub Flavored Markdown').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Tables'),
        280,
        scrollable: find
            .descendant(of: examples, matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Tables'), findsOneWidget);
      expect(workspace.active.dialect, MarkdownDialect.original);

      await tester.tap(
        find.descendant(of: dialog, matching: find.byTooltip('Close')),
      );
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
