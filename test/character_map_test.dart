import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/screens/character_map_dialog.dart';
import 'package:visor_markdown/services/unicode_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog searches Unicode ranges and emoji sequences globally',
    () async {
      final catalog = await UnicodeCatalog.load();
      expect(catalog.find('').length, greaterThan(150000));
      expect(catalog.categories(icons: false), contains('Greek and Coptic'));
      expect(catalog.categories(icons: true), contains('Flags'));
      final ideograph = catalog.find('CJK UNIFIED IDEOGRAPH-4E00');
      expect(ideograph.length, 1);
      expect(ideograph[0].glyph, '一');
      final flag = catalog.find('U+1F1FA U+1F1FE');
      expect(flag.length, 1);
      expect(flag[0].glyph, '🇺🇾');
      expect(catalog.find('check mark', icons: true).length, greaterThan(0));
    },
  );

  for (final width in [380.0, 1200.0]) {
    testWidgets('character map replaces the selection at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = WorkspaceController(watch: false);
      await tester.pumpWidget(MarkdownApp(controller: workspace));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      });

      final editor = workspace.active.editor;
      editor.value = const TextEditingValue(
        text: 'a symbol b',
        selection: TextSelection(baseOffset: 2, extentOffset: 8),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('character-map-action'));
      final reference = find.byKey(const ValueKey('markdown-reference-action'));
      expect(tester.getCenter(button).dy, tester.getCenter(reference).dy);
      expect(
        tester.getCenter(button).dx,
        greaterThan(tester.getCenter(reference).dx),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      final dialog = find.byType(CharacterMapDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('All')),
        findsOneWidget,
      );
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        'U+1F4CC',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('📌')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('PUSHPIN · U+1F4CC'));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(editor.text, 'a 📌 b');
      expect(editor.selection, const TextSelection.collapsed(offset: 4));
      final editorField = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller == editor,
      );
      expect(
        tester.widget<EditableText>(editorField).focusNode.hasFocus,
        isTrue,
      );
    });
  }
}
