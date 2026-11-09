import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/models/app_settings.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/widgets/blank_line_preview.dart';

void main() {
  test(
    'preview parser preserves empty lines while fenced code owns its blanks',
    () {
      final nodes =
          md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
            blockSyntaxes: previewBlockSyntaxes(gfm: true),
          ).parse(
            previewWithTrailingLine(
              '\nFirst\n\n\nSecond\n\n```dart\ncode\n\nmore code\n```\n',
            ),
          );
      final gaps = nodes
          .whereType<md.Element>()
          .where((n) => n.tag == BlankLineSyntax.tag)
          .toList();
      expect(gaps.map((n) => n.attributes['count']), ['1', '2', '1', '1']);
      final code = nodes.whereType<md.Element>().singleWhere(
        (n) => n.tag == 'pre',
      );
      expect(code.textContent, contains('code\n\nmore code'));
    },
  );

  Future<WorkspaceController> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(watch: false);
    await tester.pumpWidget(
      MarkdownApp(controller: c, settings: AppSettings()),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  testWidgets(
    'each empty source line adds a visible line of space in all dialects',
    (tester) async {
      final c = await setup(tester);
      for (final dialect in MarkdownDialect.values) {
        c.active.dialect = dialect;
        c.active.editor.text = 'First\n\nSecond';
        await tester.pumpAndSettle();
        final singleGap =
            tester.getTopLeft(find.text('Second')).dy -
            tester.getBottomLeft(find.text('First')).dy;
        expect(singleGap, closeTo(25.6, .1), reason: dialect.name);
        c.active.editor.text = 'First\n\n\n\nSecond';
        await tester.pumpAndSettle();
        final tripleGap =
            tester.getTopLeft(find.text('Second')).dy -
            tester.getBottomLeft(find.text('First')).dy;
        expect(tripleGap, closeTo(singleGap * 3, .1), reason: dialect.name);
        expect(c.active.editor.text, 'First\n\n\n\nSecond');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Enter at the end, leading empty lines and CRLF remain visible', (
    tester,
  ) async {
    final c = await setup(tester);
    c.active.editor.text = 'Text';
    await tester.pumpAndSettle();
    expect(find.byType(BlankLineSpacer), findsNothing);
    await tester.enterText(
      find.byKey(ValueKey('editor-${c.active.id}')),
      'Text\n',
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(BlankLineSpacer)).height,
      closeTo(25.6, .1),
    );
    c.active.editor.text = '\r\n\r\nText\r\n\r\n';
    await tester.pumpAndSettle();
    final gaps = find.byType(BlankLineSpacer);
    expect(gaps, findsNWidgets(2));
    expect(tester.getSize(gaps.first).height, closeTo(51.2, .1));
    expect(tester.getSize(gaps.last).height, closeTo(51.2, .1));
    expect(c.active.editor.text, '\r\n\r\nText\r\n\r\n');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty lines between and after list items remain visible without breaking GFM tables',
    (tester) async {
      final c = await setup(tester);
      c.active.dialect = MarkdownDialect.gfm;
      c.active.editor.text =
          '- One\n\n- Two\n\n\nAfter\n\n| A | B |\n| --- | --- |\n| X | Y |';
      await tester.pumpAndSettle();
      final firstGap =
          tester.getTopLeft(find.text('Two')).dy -
          tester.getBottomLeft(find.text('One')).dy;
      final lastGap =
          tester.getTopLeft(find.text('After')).dy -
          tester.getBottomLeft(find.text('Two')).dy;
      expect(firstGap, closeTo(25.6, .1));
      expect(lastGap, closeTo(51.2, .1));
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('table cells follow the active theme foreground', (tester) async {
    final c = await setup(tester);
    c.active.editor.text =
        '| Header | Other |\n| --- | --- |\n| Cell | Value |';
    final settings = tester
        .widget<MarkdownApp>(find.byType(MarkdownApp))
        .settings!;
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      settings.theme = mode;
      settings.update();
      await tester.pumpAndSettle();
      final table = find.byType(Table);
      final theme = Theme.of(tester.element(table));
      expect(
        theme.brightness,
        mode == ThemeMode.light ? Brightness.light : Brightness.dark,
      );
      for (final label in ['Header', 'Cell']) {
        final editable = find.byWidgetPredicate(
          (widget) => widget is EditableText && widget.controller.text == label,
        );
        final cell = tester.widget<EditableText>(editable);
        expect(cell.style.color, theme.colorScheme.onSurface);
      }
    }
  });
}
