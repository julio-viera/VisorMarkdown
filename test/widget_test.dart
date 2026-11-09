import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';

void main() {
  testWidgets('editing updates preview and tabs keep their own documents', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WorkspaceController(watch: false);
    await tester.pumpWidget(MarkdownApp(controller: controller));
    await tester.enterText(
      find.byKey(ValueKey('editor-${controller.active.id}')),
      '# Hello world\n\nFirst line\nSecond line',
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('First line\nSecond line'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    expect(controller.documents.length, 2);
    expect(controller.active.editor.text, isEmpty);
    controller.select(0);
    await tester.pumpAndSettle();
    expect(find.text('Hello world'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('closing dirty tab offers cancellation and explicit discard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(watch: false);
    await tester.pumpWidget(MarkdownApp(controller: c));
    c.active.editor.text = 'unsaved';
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.active.editor.text, 'unsaved');
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(c.active.editor.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('mobile layout exposes drawer and preview without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(watch: false);
    await tester.pumpWidget(MarkdownApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
