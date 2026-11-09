import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
