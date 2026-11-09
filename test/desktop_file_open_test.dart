import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/repositories/document_repository.dart';
import 'package:visor_markdown/services/desktop_file_open_service.dart';

class CountingFiles extends DocumentRepository {
  int reads = 0;
  @override
  Future<String> read(String path) {
    reads++;
    return super.read(path);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/desktop-files');
  Future<void> incoming(dynamic payload) =>
      binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('openRequest', payload),
        ),
        (_) {},
      );

  test('startup requests precede early live events and subsequent events are serialized', () async {
    final initial = Completer<List<dynamic>>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => initial.future,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final service = DesktopFileOpenService(channel: channel);
    final requests = <List<String>>[];
    final errors = <Object>[];
    final start = service.start(
      onOpenPaths: (paths) async {
        requests.add(paths);
        await Future<void>.delayed(Duration.zero);
      },
      onError: errors.add,
    );
    await incoming({
      'paths': ['/live á.md'],
    });
    initial.complete([
      {
        'paths': ['/initial.md', '/with spaces.md'],
      },
    ]);
    await start;
    await incoming({'paths': []});
    await service.flush();
    expect(requests, [
      ['/initial.md', '/with spaces.md'],
      ['/live á.md'],
      [],
    ]);
    expect(errors, isEmpty);
    service.dispose();
    await incoming({
      'paths': ['/ignored.md'],
    });
    expect(requests.length, 3);
  });

  test('malformed or failing requests do not prevent later opens', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => [],
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final errors = <Object>[];
    final opened = <String>[];
    final service = DesktopFileOpenService(channel: channel);
    await service.start(
      onOpenPaths: (paths) async {
        if (paths.contains('/fail.md')) {
          throw const FileSystemException('Cannot read');
        }
        opened.addAll(paths);
      },
      onError: errors.add,
    );
    await incoming({
      'paths': [123],
    });
    await incoming({
      'paths': ['/fail.md'],
    });
    await incoming({
      'paths': ['/ok.md'],
    });
    await service.flush();
    expect(errors.length, 2);
    expect(opened, ['/ok.md']);
    service.dispose();
  });

  test('same canonical file focuses its tab without reading or losing unsaved changes', () async {
    final directory = await Directory.systemTemp.createTemp('visor-single-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/archivo á con espacios.md');
    await file.writeAsString('# Original');
    final alias = Link('${directory.path}/alias.md');
    await alias.create(file.path);
    final files = CountingFiles();
    final workspace = WorkspaceController(repository: files, watch: false);
    addTearDown(workspace.dispose);
    await Future.wait([
      workspace.openPath(file.path),
      workspace.openPath(alias.path),
    ]);
    expect(files.reads, 1);
    expect(workspace.documents.length, 1);
    final document = workspace.active;
    document.editor.text = '# Unsaved changes';
    workspace.add(text: 'Other unsaved document');
    await workspace.openPath(file.uri.toString());
    expect(workspace.active, same(document));
    expect(workspace.active.editor.text, '# Unsaved changes');
    expect(workspace.active.dirty, true);
    expect(files.reads, 1);
    await file.delete();
    await workspace.openPath(file.path);
    expect(workspace.active, same(document));
    expect(files.reads, 1);
    await expectLater(
      workspace.openPath('${directory.path}/missing.md'),
      throwsA(isA<FileSystemException>()),
    );
    final next = File('${directory.path}/next.md');
    await next.writeAsString('# Next');
    await workspace.openPath(next.path);
    expect(workspace.documents.length, 3);
    expect(workspace.active.editor.text, '# Next');
  });

  test('repeated Android URI selects the original imported tab without replacing edits', () {
    final workspace = WorkspaceController(watch: false);
    addTearDown(workspace.dispose);
    workspace.importDocument(
      OpenedFile('one.md', 'original', null, sourceId: 'content://docs/one'),
    );
    final document = workspace.active;
    document.editor.text = 'unsaved';
    workspace.importDocument(
      OpenedFile('two.md', 'second', null, sourceId: 'content://docs/two'),
    );
    workspace.importDocument(
      OpenedFile(
        'renamed.md',
        'new disk text',
        null,
        sourceId: 'content://docs/one',
      ),
    );
    expect(workspace.documents.length, 2);
    expect(workspace.active, same(document));
    expect(workspace.active.editor.text, 'unsaved');
  });
}
