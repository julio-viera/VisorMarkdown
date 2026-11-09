import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/widgets/safe_markdown_image.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

void main() {
  testWidgets('authorizing an external image refreshes its visible references', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'visor-image-preview-',
    );
    final external = File('${directory.path}/external.png')
      ..writeAsBytesSync(base64Decode(pixel));
    final other = File('${directory.path}/other.png')
      ..writeAsBytesSync(base64Decode(pixel));
    final documentDir = Directory('${directory.path}/docs')..createSync();
    final c = WorkspaceController(watch: false);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      directory.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    c.active
      ..path = '${documentDir.path}/example.md'
      ..editor.text =
          '![First](${external.uri})\n\n![Second](${external.uri})\n\n![Other](${other.uri})';
    await tester.pumpWidget(MarkdownApp(controller: c));

    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    final first = find.text('Load image: First');
    await waitFor(() => first.evaluate().isNotEmpty);
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Load image'));
    await tester.pumpAndSettle();

    final rendered = find.descendant(
      of: find.byType(SafeMarkdownImage),
      matching: find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      ),
    );
    await waitFor(() => rendered.evaluate().length == 2);
    expect(rendered, findsNWidgets(2));
    expect(find.text('Load image: Other'), findsOneWidget);
  });
}
