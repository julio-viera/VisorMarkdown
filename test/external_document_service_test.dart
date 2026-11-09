import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/repositories/document_repository.dart';
import 'package:visor_markdown/services/external_document_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/file-open');
  Future<void> incoming(dynamic payload) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('openDocument', payload),
      ),
      (_) {},
    );
  }

  test('startup and live Android documents deliver UTF-8 content and safe import names', () async {
    final files = <OpenedFile>[];
    final errors = <Object>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => [
        {
          'name': 'documento á.md',
          'sourceId': 'content://documents/first',
          'bytes': Uint8List.fromList(utf8.encode('# Español')),
        },
      ],
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final service = ExternalDocumentService(channel: channel);
    await service.start(onDocument: files.add, onError: errors.add);
    expect(files.single.name, 'documento á.md');
    expect(files.single.text, '# Español');
    expect(files.single.path, isNull);
    expect(files.single.sourceId, 'content://documents/first');
    await incoming({
      'name': 'second.md',
      'bytes': Uint8List.fromList(utf8.encode('second')),
    });
    expect(files.length, 2);
    expect(errors, isEmpty);
    service.dispose();
    await incoming({'name': 'late.md', 'bytes': Uint8List(0)});
    expect(files.length, 2);
  });
  test('Android read failures and malformed payloads report errors without opening a document', () async {
    final files = <OpenedFile>[];
    final errors = <Object>[];
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
    final service = ExternalDocumentService(channel: channel);
    await service.start(onDocument: files.add, onError: errors.add);
    await incoming({'error': 'Permission denied'});
    await incoming({'name': 'missing.md'});
    await incoming({
      'name': 'invalid.md',
      'bytes': Uint8List.fromList([0xff]),
    });
    expect(files, isEmpty);
    expect(errors.length, 3);
    service.dispose();
  });
  test('imported documents replace only the pristine blank and preserve unsaved tabs', () {
    final c = WorkspaceController(watch: false);
    addTearDown(c.dispose);
    c.importDocument(OpenedFile('first.md', 'first', null));
    expect(c.documents.length, 1);
    expect(c.active.title, 'first.md');
    expect(c.active.path, isNull);
    expect(c.active.dirty, false);
    c.active.editor.text = 'unsaved edits';
    c.importDocument(OpenedFile('second.md', 'second', null));
    expect(c.documents.length, 2);
    expect(c.documents.first.editor.text, 'unsaved edits');
    expect(c.documents.first.dirty, true);
  });
}
