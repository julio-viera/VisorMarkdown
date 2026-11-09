import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/repositories/document_repository.dart';
import 'package:visor_markdown/services/document_limits.dart';

void main() {
  test(
    'save through a symbolic link preserves the link and file mode',
    () async {
      final directory = await Directory.systemTemp.createTemp('visor-write-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/source.md')
          .writeAsString('old');
      final link = await Link('${directory.path}/link.md').create(file.path);
      expect((await Process.run('chmod', ['640', file.path])).exitCode, 0);

      await DocumentRepository().write(link.path, 'new');

      expect(await link.exists(), isTrue);
      expect(await file.readAsString(), 'new');
      expect((await file.stat()).mode & 0x1ff, 0x1a0);
      expect(await directory.list().length, 2);
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );

  test('a rejected save leaves the existing contents intact', () async {
    final directory = await Directory.systemTemp.createTemp('visor-write-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/source.md').writeAsString('old');
    expect((await Process.run('chmod', ['444', file.path])).exitCode, 0);

    await expectLater(
      DocumentRepository().write(file.path, 'new'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'old');
    expect(await directory.list().length, 1);
  }, skip: !Platform.isLinux && !Platform.isMacOS);

  test('the shared reader rejects a named pipe before reading', () async {
    final directory = await Directory.systemTemp.createTemp('visor-read-');
    addTearDown(() => directory.delete(recursive: true));
    final pipe = File('${directory.path}/image.png');
    expect((await Process.run('mkfifo', [pipe.path])).exitCode, 0);

    await expectLater(
      DocumentLimits.readBytes(pipe, 4096).timeout(const Duration(seconds: 1)),
      throwsA(isA<FileSystemException>()),
    );
  }, skip: !Platform.isLinux);
}
