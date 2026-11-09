import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';

void main() {
  final text = List.generate(
    90,
    (i) =>
        '# Section $i\n\nA paragraph with **bold text** and a [link](https://example.com).\n\n- First item\n- Second item\n',
  ).join('\n');

  Future<WorkspaceController> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(watch: false);
    c.active.editor.text = text;
    await tester.pumpWidget(MarkdownApp(controller: c));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  testWidgets('split can resize, hide and restore the preview', (tester) async {
    final c = await setup(tester);
    final doc = c.active;
    final editor = find.byKey(ValueKey('numbered-editor-${doc.id}'));
    final preview = find.byKey(ValueKey('preview-${doc.id}'));
    final divider = find.byKey(const ValueKey('preview-divider'));
    final initialWidth = tester.getSize(editor).width;

    await tester.drag(divider, const Offset(140, 0));
    await tester.pumpAndSettle();
    final resizedWidth = tester.getSize(editor).width;
    expect(resizedWidth, greaterThan(initialWidth + 100));

    await tester.tap(find.byTooltip('Hide preview'));
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
    expect(divider, findsNothing);
    expect(tester.getSize(editor).width, 1200);

    doc.scroll.jumpTo(350);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show preview'));
    await tester.pumpAndSettle();
    expect(tester.getSize(editor).width, closeTo(resizedWidth, 1));
    expect(preview, findsOneWidget);
    expect(doc.scrollSync.readPreview!(), greaterThan(0));

    await tester.drag(divider, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(preview).width, greaterThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs keep independent preview visibility and width', (
    tester,
  ) async {
    final c = await setup(tester);
    final first = c.active;
    final divider = find.byKey(const ValueKey('preview-divider'));
    double editorWidth() => tester
        .getSize(find.byKey(ValueKey('numbered-editor-${c.active.id}')))
        .width;

    final defaultWidth = editorWidth();
    await tester.drag(divider, const Offset(140, 0));
    await tester.pumpAndSettle();
    final firstWidth = editorWidth();
    expect(firstWidth, greaterThan(defaultWidth));
    await tester.tap(find.byTooltip('Hide preview'));
    await tester.pumpAndSettle();

    c.add(text: text);
    final second = c.active;
    await tester.pumpAndSettle();
    expect(divider, findsOneWidget);
    expect(editorWidth(), closeTo(defaultWidth, 1));
    await tester.drag(divider, const Offset(-100, 0));
    await tester.pumpAndSettle();
    final secondWidth = editorWidth();
    expect(secondWidth, lessThan(defaultWidth));

    c.select(0);
    await tester.pumpAndSettle();
    expect(divider, findsNothing);
    await tester.tap(find.byTooltip('Show preview'));
    await tester.pumpAndSettle();
    expect(editorWidth(), closeTo(firstWidth, 1));

    c.select(1);
    await tester.pumpAndSettle();
    expect(editorWidth(), closeTo(secondWidth, 1));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('preview-${second.id}')), findsOneWidget);
    c.select(0);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('numbered-editor-${first.id}')), findsOneWidget);
    c.select(1);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('preview-${second.id}')), findsOneWidget);
  });

  testWidgets('distant editor jump aligns the matching preview heading', (
    tester,
  ) async {
    final c = await setup(tester);
    final doc = c.active;
    final source = List.generate(
      100,
      (i) =>
          '# Heading $i\n\n${i < 45 || i == 52 ? 'Short.' : 'Text that wraps. ' * 45}',
    ).join('\n\n');
    doc.editor.text = source;
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final destination = source.indexOf('# Heading 52');
    doc.scrollSync.revealEditor!(destination);
    await tester.pumpAndSettle();
    expect(find.text('Heading 52'), findsOneWidget);
    expect(doc.scrollSync.readPreview!(), closeTo(destination, 4));
    expect(doc.scrollSync.readEditor!(), closeTo(destination, 4));

    final preview = find.byKey(ValueKey('preview-${doc.id}'));
    final nextHeading = tester.getTopLeft(find.text('Heading 53')).dy;
    final previewTop = tester.getTopLeft(preview).dy;
    doc.previewScroll.jumpTo(
      doc.previewScroll.offset + nextHeading - previewTop,
    );
    await tester.pumpAndSettle();
    expect(
      doc.scrollSync.readEditor!(),
      closeTo(source.indexOf('# Heading 53'), 5),
    );
  });

  testWidgets('returning to the editor top resets the preview origin', (
    tester,
  ) async {
    final c = await setup(tester);
    final doc = c.active;
    final preview = find.byKey(ValueKey('preview-${doc.id}'));
    final heading = find.text('Section 0');
    final topPadding =
        tester.getTopLeft(heading).dy - tester.getTopLeft(preview).dy;
    doc.scrollSync.revealEditor!(text.indexOf('# Section 60'));
    await tester.pumpAndSettle();
    expect(heading, findsNothing);

    // Move back near the beginning before returning all the way to the top.
    doc.scrollSync.revealEditor!(text.indexOf('# Section 1'));
    await tester.pumpAndSettle();
    doc.scroll.jumpTo(doc.scroll.position.minScrollExtent);
    await tester.pumpAndSettle();

    expect(doc.scrollSync.readPreview!(), 0);
    expect(doc.previewScroll.offset, 0);
    expect(doc.previewScroll.position.minScrollExtent, 0);
    expect(
      tester.getTopLeft(heading).dy - tester.getTopLeft(preview).dy,
      closeTo(topPadding, .5),
    );
  });

  testWidgets(
    'only the editor shows a scrollbar and the preview still scrolls',
    (tester) async {
      final c = await setup(tester);
      final doc = c.active;
      final largeSource = List.filled(5, text).join('\n\n');
      doc.editor.text = largeSource;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final editor = tester.getRect(
        find.byKey(ValueKey('numbered-editor-${doc.id}')),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RawScrollbar &&
              (widget.controller == doc.scroll ||
                  widget.controller == doc.previewScroll),
        ),
        findsOneWidget,
      );
      final pointer = TestPointer(21, PointerDeviceKind.mouse);
      final grabPoint = Offset(editor.right - 10, editor.top + 15);
      await tester.sendEventToBinding(pointer.hover(grabPoint));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
          pointer.device,
        ),
        SystemMouseCursors.grab,
      );

      final editorThumb = await tester.startGesture(
        grabPoint,
        kind: PointerDeviceKind.mouse,
      );
      await editorThumb.moveBy(const Offset(0, 80));
      await tester.pump();
      await editorThumb.moveBy(const Offset(0, 300));
      await tester.pump();
      expect(doc.scroll.offset, greaterThan(0));
      expect(doc.scrollSync.readPreview!(), 0);
      await editorThumb.up();
      await tester.pumpAndSettle();
      expect(doc.scrollSync.readPreview!(), greaterThan(0));
      doc.scroll.jumpTo(doc.scroll.position.minScrollExtent);
      await tester.pumpAndSettle();

      final preview = tester.getRect(find.byKey(ValueKey('preview-${doc.id}')));
      await tester.sendEventToBinding(pointer.hover(preview.center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pumpAndSettle();

      expect(doc.scrollSync.readPreview!(), greaterThan(0));
      expect(doc.scroll.offset, greaterThan(0));
      expect(
        doc.scrollSync.readEditor!(),
        closeTo(doc.scrollSync.readPreview!()!, 110),
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets('wheel scrolling never reverses either panel on mixed blocks', (
    tester,
  ) async {
    final c = await setup(tester);
    final doc = c.active;
    doc.editor.text = List.generate(
      100,
      (i) => i % 12 < 6
          ? '# Section $i\n\nA short paragraph.'
          : '## Section $i\n\n${'A long paragraph that wraps. ' * 16}',
    ).join('\n\n');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    for (final panel in ['editor', 'preview']) {
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(find.byKey(ValueKey('$panel-${doc.id}'))),
        ),
      );
      for (final direction in [1, -1]) {
        final start = doc.scrollSync.readPreview!()!;
        for (var i = 0; i < 30; i++) {
          var editorBefore = doc.scroll.offset;
          var previewBefore = doc.scrollSync.readPreview!()!;
          await tester.sendEventToBinding(
            pointer.scroll(Offset(0, 85 * direction.toDouble())),
          );
          await tester.pump();
          for (var frame = 0; frame < 3; frame++) {
            expect(
              (doc.scroll.offset - editorBefore) * direction,
              greaterThanOrEqualTo(-.5),
            );
            expect(
              (doc.scrollSync.readPreview!()! - previewBefore) * direction,
              greaterThanOrEqualTo(-.5),
            );
            editorBefore = doc.scroll.offset;
            previewBefore = doc.scrollSync.readPreview!()!;
            await tester.pump(const Duration(milliseconds: 16));
          }
        }
        expect(
          (doc.scrollSync.readPreview!()! - start) * direction,
          greaterThan(100),
        );
      }
    }
  });

  testWidgets('each tab retains its own synchronized source position', (
    tester,
  ) async {
    final c = await setup(tester);
    final first = c.active;
    final firstOffset = text.indexOf('# Section 40');
    first.scrollSync.revealEditor!(firstOffset);
    await tester.pumpAndSettle();
    c.add(text: text);
    await tester.pumpAndSettle();
    expect(c.active.scrollSync.readPreview!(), 0);
    final secondOffset = text.indexOf('# Section 70');
    c.active.scrollSync.revealEditor!(secondOffset);
    await tester.pumpAndSettle();
    c.select(0);
    await tester.pumpAndSettle();
    expect(first.scrollSync.readEditor!(), closeTo(firstOffset, 4));
    expect(first.scrollSync.readPreview!(), closeTo(firstOffset, 4));
    c.select(1);
    await tester.pumpAndSettle();
    expect(c.active.scrollSync.readEditor!(), closeTo(secondOffset, 4));
    expect(c.active.scrollSync.readPreview!(), closeTo(secondOffset, 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to an evicted preview restores the tab scroll', (
    tester,
  ) async {
    final c = await setup(tester);
    final first = c.active;
    final anchor = text.indexOf('# Section 40');
    first.scrollSync.revealEditor!(anchor);
    await tester.pumpAndSettle();

    c.add(text: List.filled(600, text.substring(0, 100)).join('\n\n'));
    await tester.pumpAndSettle();
    expect(first.previewScroll.hasClients, isFalse);
    await tester.tap(find.byKey(ValueKey('tab-${first.id}')));
    await tester.pumpAndSettle();

    expect(first.scrollSync.readEditor!(), closeTo(anchor, 4));
    expect(first.scrollSync.readPreview!(), closeTo(anchor, 4));
  });

  testWidgets('switching mobile panels restores the visible source block', (
    tester,
  ) async {
    final c = await setup(tester);
    final doc = c.active;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final anchor = text.indexOf('# Section 40');
    doc.scrollSync.revealEditor!(anchor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(doc.scroll.hasClients, false);
    expect(doc.scrollSync.readPreview!(), closeTo(anchor, 4));
    await tester.drag(
      find.byKey(ValueKey('preview-${doc.id}')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final newAnchor = doc.scrollSync.readPreview!()!;
    expect(newAnchor, greaterThan(anchor));
    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();
    expect(doc.scrollSync.readEditor!(), closeTo(newAnchor, 45));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preview that fits on screen does not reset the editor scroll', (
    tester,
  ) async {
    final c = await setup(tester);
    // Definitions keep the source long without rendering visible content.
    // Empty lines now correctly occupy space in the preview.
    c.active.editor.text =
        '${List.generate(600, (i) => '[ref$i]: https://example.com/$i').join('\n')}\n# Short';
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(c.active.previewScroll.position.maxScrollExtent, 0);
    c.active.scroll.jumpTo(c.active.scroll.position.maxScrollExtent * .5);
    await tester.pumpAndSettle();
    expect(
      c.active.scroll.offset,
      closeTo(c.active.scroll.position.maxScrollExtent * .5, 1),
    );
    expect(c.active.previewScroll.offset, 0);
    c.close(c.active);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
