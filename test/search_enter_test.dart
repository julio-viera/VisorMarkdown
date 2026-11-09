import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';

void main() {
  testWidgets(
    'repeated Enter advances, reveals matches and wraps without losing search focus',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkspaceController(watch: false);
      c.active.editor.text = List.generate(
        200,
        (i) => i % 80 == 0 ? 'target' : 'Line $i',
      ).join('\n');
      await tester.pumpWidget(MarkdownApp(controller: c));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('search'));
      await tester.enterText(search, 'target');
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, 1);
      expect(c.active.scroll.offset, greaterThan(0));
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, 2);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, 0);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, 1);
      await tester.enterText(search, 'missing');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, -1);
      await tester.tap(find.byKey(const ValueKey('clear-search')));
      await tester.pumpAndSettle();
      expect(c.active.query, isEmpty);
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('search-count'))).data,
        '0/0',
      );
      await tester.enterText(search, 'target');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(c.active.matchIndex, 1);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
