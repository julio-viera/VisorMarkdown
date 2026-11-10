import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/repositories/document_repository.dart';

class SaveRepository extends DocumentRepository {
  @override
  Future<String> canonicalPath(String path) async =>
      path == '/alias.md' ? '/saved.md' : path;
  String disk = 'original';
  String? changeBeforeReplace;
  bool fail = false;
  bool cancel = false;
  String destination = '/saved.md';
  int writes = 0;
  @override
  Future<String> read(String path) async => disk;
  @override
  Future<String?> stamp(String path) async => disk;
  @override
  Future<void> write(
    String path,
    String text, {
    Future<void> Function()? beforeReplace,
  }) async {
    if (changeBeforeReplace case final change?) {
      disk = change;
      changeBeforeReplace = null;
    }
    if (beforeReplace != null) await beforeReplace();
    if (fail) throw Exception('write failed');
    disk = text;
    writes++;
  }

  @override
  Future<String?> pickSavePath(String name, String extension) async =>
      cancel ? null : destination;
}

void main() {
  Future<WorkspaceController> setup(
    WidgetTester tester,
    SaveRepository repo, {
    bool opened = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(repository: repo, watch: false);
    if (opened) await c.openPath('/saved.md');
    await tester.pumpWidget(MarkdownApp(controller: c));
    c.active.editor.text = 'local';
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  testWidgets('cancelled Save as keeps unsaved changes', (tester) async {
    final repo = SaveRepository()..cancel = true;
    final c = await setup(tester, repo, opened: false);
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    expect(c.active.dirty, true);
    expect(c.active.path, isNull);
    expect(repo.writes, 0);
  });
  testWidgets('Save as blocks a destination open in another tab', (
    tester,
  ) async {
    final repo = SaveRepository()..destination = '/alias.md';
    final c = await setup(tester, repo);
    c.add();
    c.active.editor.text = 'another draft';
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('already open'), findsOneWidget);
    expect(repo.writes, 0);
    expect(c.active.path, isNull);
    expect(c.active.dirty, true);
  });

  testWidgets('a second external change requires a fresh confirmation', (
    tester,
  ) async {
    final repo = SaveRepository();
    final c = await setup(tester, repo);
    repo.disk = 'first external change';
    repo.changeBeforeReplace = 'second external change';

    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overwrite'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.disk, 'second external change');
    expect(repo.writes, 0);
    expect(c.active.dirty, true);
    await tester.tap(find.text('Overwrite'));
    await tester.pumpAndSettle();
    expect(repo.disk, 'local');
    expect(repo.writes, 1);
    expect(c.active.dirty, false);
  });

  testWidgets('failed write keeps dirty state and reports the failure', (
    tester,
  ) async {
    final repo = SaveRepository()..fail = true;
    final c = await setup(tester, repo);
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    expect(c.active.dirty, true);
    expect(repo.disk, 'original');
    expect(find.textContaining('write failed'), findsOneWidget);
  });
  testWidgets(
    'save conflict requires explicit overwrite and then marks snapshot saved',
    (tester) async {
      final repo = SaveRepository();
      final c = await setup(tester, repo);
      repo.disk = 'external';
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.disk, 'external');
      expect(c.active.dirty, true);
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overwrite'));
      await tester.pumpAndSettle();
      expect(repo.disk, 'local');
      expect(c.active.dirty, false);
      expect(repo.writes, 1);
    },
  );
}
