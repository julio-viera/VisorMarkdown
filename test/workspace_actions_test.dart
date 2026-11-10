import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/repositories/document_repository.dart';
import 'package:visor_markdown/widgets/document_tab_strip.dart';
import 'package:visor_markdown/widgets/app_logo.dart';

class ActionRepository extends DocumentRepository {
  @override
  Future<String> canonicalPath(String path) async => path;
  final files = <String, String>{
    '/first.md': 'first',
    '/second.md': 'second',
    '/next.md': '# Next',
  };
  List<OpenedFile> picked = [OpenedFile('next.md', '# Next', '/next.md')];
  bool cancelSave = false;
  bool failWrite = false;
  final writes = <String>[];
  @override
  Future<List<OpenedFile>> pick() async => picked;
  @override
  Future<String> read(String path) async => files[path]!;
  @override
  Future<String?> stamp(String path) async => files[path];
  @override
  Future<void> write(
    String path,
    String text, {
    Future<void> Function()? beforeReplace,
  }) async {
    if (beforeReplace != null) await beforeReplace();
    if (failWrite) throw Exception('write failed');
    files[path] = text;
    writes.add(path);
  }

  @override
  Future<String?> pickSavePath(String name, String extension) async =>
      cancelSave ? null : '/saved.md';
}

void main() {
  Future<WorkspaceController> setup(
    WidgetTester tester,
    ActionRepository repo,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(repository: repo, watch: false);
    await tester.pumpWidget(MarkdownApp(controller: c));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  testWidgets(
    'open replaces the current tab while preserving the other documents',
    (tester) async {
      final repo = ActionRepository();
      final c = await setup(tester, repo);
      c.active.editor.text = 'keep this other tab';
      c.add();
      final id = c.active.id;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open'));
      await tester.pumpAndSettle();
      expect(c.documents.length, 2);
      expect(c.active.id, id);
      expect(c.active.path, '/next.md');
      expect(c.active.editor.text, '# Next');
      expect(c.active.dirty, false);
      expect(c.documents.first.editor.text, 'keep this other tab');
      c.active.editor.text = '# Next edited';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(c.documents.length, 2);
      expect(c.active.id, id);
      expect(repo.files['/next.md'], '# Next edited');
      expect(c.active.dirty, false);
    },
  );

  testWidgets(
    'opening an existing file selects its tab without replacing edits',
    (tester) async {
      final repo = ActionRepository();
      final c = await setup(tester, repo);
      await c.openPath('/next.md');
      final existing = c.active;
      existing.editor.text = 'unsaved existing edits';
      c.add(text: 'unsaved current edits');
      final other = c.active;
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open'));
      await tester.pumpAndSettle();

      expect(c.active, same(existing));
      expect(c.documents, [existing, other]);
      expect(existing.editor.text, 'unsaved existing edits');
      expect(other.editor.text, 'unsaved current edits');
    },
  );

  testWidgets(
    'open prompts before replacement and cancellation preserves the document',
    (tester) async {
      final c = await setup(tester, ActionRepository());
      c.active.editor.text = 'local';
      final target = c.active;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Save changes before opening another file?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.active, same(target));
      expect(c.active.editor.text, 'local');
      await tester.tap(find.byTooltip('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(c.documents.length, 1);
      expect(c.active.id, target.id);
      expect(c.active.editor.text, '# Next');
    },
  );

  testWidgets(
    'save before opening writes the old document before replacing its tab',
    (tester) async {
      final repo = ActionRepository();
      final c = await setup(tester, repo);
      await c.openPath('/first.md');
      c.active.editor.text = 'edited first';
      final id = c.active.id;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.files['/first.md'], 'edited first');
      expect(repo.writes, ['/first.md']);
      expect(c.active.path, '/next.md');
      expect(c.active.id, id);
      expect(c.documents.length, 1);
    },
  );

  testWidgets('cancelled or failed save prevents opening a replacement', (
    tester,
  ) async {
    final repo = ActionRepository()..cancelSave = true;
    final c = await setup(tester, repo);
    c.active.editor.text = 'unsaved';
    final target = c.active;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(c.active, same(target));
    expect(c.active.dirty, true);
    repo.cancelSave = false;
    repo.failWrite = true;
    await tester.tap(find.byTooltip('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(c.active, same(target));
    expect(c.active.editor.text, 'unsaved');
    expect(find.textContaining('write failed'), findsOneWidget);
  });

  testWidgets(
    'clipboard buttons copy Markdown and paste at the editor selection',
    (tester) async {
      String clipboard = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final c = await setup(tester, ActionRepository());
      c.active.editor.text = '# Hello Markdown';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy Markdown'));
      await tester.pumpAndSettle();
      expect(clipboard, '# Hello Markdown');
      clipboard = 'world';
      c.active.editor.selection = const TextSelection(
        baseOffset: 8,
        extentOffset: 16,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Paste Markdown'));
      await tester.pumpAndSettle();
      expect(c.active.editor.text, '# Hello world');
      expect(c.active.editor.selection.baseOffset, 13);
      expect(c.active.dirty, true);
    },
  );

  testWidgets(
    'app exit can be cancelled and saves dirty background tabs before exit',
    (tester) async {
      final repo = ActionRepository();
      final c = await setup(tester, repo);
      await c.openPath('/first.md');
      c.active.editor.text = 'first edited';
      await c.openPath('/second.md');
      c.active.editor.text = 'second edited';
      await tester.pumpAndSettle();
      final cancelled = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('Save changes before exiting?'), findsOneWidget);
      expect(find.text('first.md'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await cancelled, AppExitResponse.cancel);
      expect(repo.writes, isEmpty);
      final accepted = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes before exiting?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(await accepted, AppExitResponse.exit);
      expect(repo.files['/first.md'], 'first edited');
      expect(repo.files['/second.md'], 'second edited');
      expect(c.documents.every((d) => !d.dirty), true);
    },
  );

  testWidgets(
    'tab strip scrolls and reveals new tabs while its actions remain fixed',
    (tester) async {
      final c = await setup(tester, ActionRepository());
      expect(find.byType(AppBar), findsNothing);
      final action = find.byKey(const ValueKey('new-tab-action'));
      final initialPosition = tester.getTopLeft(action);
      for (var i = 0; i < 20; i++) {
        c.add();
      }
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('tabs-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, greaterThan(0));
      expect(
        find.byKey(ValueKey('tab-${c.active.id}')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getTopLeft(action), initialPosition);
      await tester.tap(find.byKey(const ValueKey('tabs-back')));
      await tester.pumpAndSettle();
      expect(
        scrollable.position.pixels,
        lessThan(scrollable.position.maxScrollExtent),
      );
      final manuallyScrolled = scrollable.position.pixels;
      c.changed(); // File checks and editor updates must not undo manual scrolling.
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, manuallyScrolled);
      c.select(0);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      expect(
        find.byKey(ValueKey('tab-${c.active.id}')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getTopLeft(action), initialPosition);
      final strip = tester.getRect(find.byType(DocumentTabStrip));
      expect(
        tester.getCenter(find.byTooltip('Open')).dy,
        greaterThan(strip.bottom),
      );
      expect(
        tester.getCenter(find.byTooltip('Save')).dy,
        greaterThan(strip.bottom),
      );
      final footer = find.byKey(const ValueKey('status-bar'));
      expect(tester.getSize(footer).height, 30);
      expect(
        find.descendant(of: footer, matching: find.byType(AppLogo)),
        findsOneWidget,
      );
      expect(tester.getCenter(find.byTooltip('About')).dx, greaterThan(1100));
      expect(tester.takeException(), isNull);
    },
  );
}
