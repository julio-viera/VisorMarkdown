import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/screens/workspace_screen.dart';
import 'package:visor_markdown/widgets/numbered_editor.dart';

void main() {
  Future<WorkspaceController> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'monospace': ['DejaVuSansMono'],
        'sans-serif': [
          'LiberationSans-Regular',
          'LiberationSans-Bold',
          'LiberationSans-Italic',
          'LiberationSans-BoldItalic',
        ],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final name in entry.value) {
          loader.addFont(rootBundle.load('assets/fonts/$name.ttf'));
        }
        await loader.load();
      }
    });
    final c = WorkspaceController(watch: false);
    c.active.editor.text =
        'First\n${List.filled(22, 'wrapped').join(' ')}\n\nFourth\n${List.generate(150, (i) => 'Content line $i').join('\n')}';
    await tester.pumpWidget(MarkdownApp(controller: c));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  List<LineNumberPlacement> checkAlignment(
    WidgetTester tester,
    WorkspaceController c,
  ) {
    final field = find.byKey(ValueKey('editor-${c.active.id}'));
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    final render = editable.renderEditable;
    final gutter = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is LineNumberPainter,
    );
    final painter =
        tester.widget<CustomPaint>(gutter).painter! as LineNumberPainter;
    final labels = painter.layoutNumbers(tester.getSize(gutter));
    expect(labels, isNotEmpty);
    final origin = render.localToGlobal(Offset.zero).dy;
    final firstCaret = render
        .getEndpointsForSelection(const TextSelection.collapsed(offset: 0))
        .first
        .point
        .dy;
    final firstBaseline = render.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final gutterTop = tester.getTopLeft(gutter).dy;
    for (final label in labels) {
      final sourceCaret = render
          .getEndpointsForSelection(
            TextSelection.collapsed(offset: painter.offsets[label.number - 1]),
          )
          .first
          .point
          .dy;
      final expectedBaseline =
          origin +
          firstBaseline +
          sourceCaret -
          firstCaret -
          c.active.scroll.offset;
      expect(
        gutterTop + label.baseline,
        closeTo(expectedBaseline, .1),
        reason: 'line ${label.number}, size ${editable.widget.style.fontSize}',
      );
    }
    return labels;
  }

  testWidgets(
    'Tab inserts four spaces, replaces selection and keeps editor focus',
    (tester) async {
      final c = await setup(tester);
      c.active.editor.text = 'abcdef';
      await tester.pumpAndSettle();
      final field = find.byKey(ValueKey('editor-${c.active.id}'));
      await tester.tap(field);
      c.active.editor.selection = const TextSelection.collapsed(offset: 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(c.active.editor.text, 'ab    cdef');
      expect(c.active.editor.selection.baseOffset, 6);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, true);
      c.active.editor.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(c.active.editor.text, 'ab        cdef');
      expect(c.active.editor.selection.baseOffset, 10);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, true);
    },
  );

  testWidgets(
    'number baselines align with real editor text across fonts, sizes and wrapped lines',
    (tester) async {
      final c = await setup(tester);
      final settings = tester
          .widget<WorkspaceScreen>(find.byType(WorkspaceScreen))
          .settings;
      for (final family in ['monospace', 'sans-serif']) {
        for (final size in [10.0, 14.0, 24.0, 32.0]) {
          settings.editor.family = family;
          settings.editor.size = size;
          settings.editor.bold = size == 24;
          settings.editor.italic = size == 32;
          settings.update();
          await tester.pumpAndSettle();
          c.active.scroll.jumpTo(0);
          await tester.pumpAndSettle();
          final labels = checkAlignment(tester, c);
          expect(labels.first.number, 1);
          final third = labels.where((l) => l.number == 3);
          if (third.isNotEmpty && size >= 24) {
            expect(
              third.single.top - labels.first.top,
              greaterThan(size * 1.5 * 2),
            );
          }
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'numbers follow scroll, edits, empty lines, text scaling and mobile resizing',
    (tester) async {
      final c = await setup(tester);
      c.active.scroll.jumpTo(c.active.scroll.position.maxScrollExtent * .6);
      await tester.pumpAndSettle();
      expect(checkAlignment(tester, c).first.number, greaterThan(1));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      checkAlignment(tester, c);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      checkAlignment(tester, c);
      c.active.editor.text = '\nEnd\n';
      await tester.pumpAndSettle();
      expect(checkAlignment(tester, c).map((l) => l.number), [1, 2, 3]);
      c.active.editor.text = '';
      await tester.pumpAndSettle();
      expect(checkAlignment(tester, c).single.number, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
