import 'dart:typed_data' show Endian;
import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/repositories/document_repository.dart';
import 'package:visor_markdown/services/document_limits.dart';
import 'package:visor_markdown/services/safe_image_loader.dart';
import 'package:visor_markdown/widgets/search_editor_controller.dart';
import 'package:visor_markdown/widgets/numbered_editor.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

class CountingRepository extends DocumentRepository {
  int reads = 0;
  @override
  Future<String> read(String path) {
    reads++;
    return super.read(path);
  }
}

void main() {
  test('unchanged files skip reads and notifications; edits, deletion and recreation are detected', () async {
    final directory = await Directory.systemTemp.createTemp('visor-watch-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/doc.md');
    await file.writeAsString('before');
    final repo = CountingRepository();
    final workspace = WorkspaceController(repository: repo, watch: false);
    addTearDown(workspace.dispose);
    await workspace.openPath(file.path);
    await workspace.checkFiles();
    repo.reads = 0;
    var notifications = 0;
    workspace.addListener(() => notifications++);
    await workspace.checkFiles();
    await workspace.checkFiles();
    expect(repo.reads, 0);
    expect(notifications, 0);
    final date = await file.lastModified();
    await file.writeAsString('new content');
    await file.setLastModified(date);
    await workspace.checkFiles();
    expect(workspace.active.externalText, 'new content');
    expect(repo.reads, 1);
    await file.delete();
    await workspace.checkFiles();
    expect(workspace.active.missing, true);
    await file.writeAsString('returned');
    await workspace.checkFiles();
    expect(workspace.active.missing, false);
    expect(workspace.active.externalText, 'returned');
    // Save conflict checks use read(), independently of cached metadata.
    expect(await repo.read(file.path), 'returned');
  });

  test(
    'search cache survives selection and invalidates on text or query changes',
    () {
      final controller = SearchEditorController(text: 'one ONE [x]');
      addTearDown(controller.dispose);
      final matches = controller.matchesFor('one');
      expect(matches.length, 2);
      controller.selection = const TextSelection.collapsed(offset: 2);
      expect(identical(matches, controller.matchesFor('one')), true);
      expect(controller.matchesFor('[x]').length, 1);
      controller.text = 'no matches';
      expect(controller.matchesFor('one'), isEmpty);
      expect(controller.matchesFor(''), isEmpty);
    },
  );

  test('documents are bounded by UTF8 size and logical line count', () async {
    expect(
      () => DocumentLimits.decode(Uint8List(DocumentLimits.maxBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => DocumentLimits.validate('é' * (DocumentLimits.maxBytes ~/ 2 + 1)),
      throwsFormatException,
    );
    expect(
      () => DocumentLimits.validate('\n' * DocumentLimits.maxLines),
      throwsFormatException,
    );
    DocumentLimits.validate('a\r\nb\rc\nd');
    final directory = await Directory.systemTemp.createTemp('visor-limits-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/large.md');
    await file.writeAsBytes(Uint8List(DocumentLimits.maxBytes + 1));
    await expectLater(
      DocumentRepository().read(file.path),
      throwsFormatException,
    );
  });

  test('oversized edits preserve text and selection and notify the user', () {
    const old = TextEditingValue(
      text: 'keep',
      selection: TextSelection.collapsed(offset: 2),
    );
    var rejected = false;
    final formatter = DocumentInputFormatter(() => rejected = true);
    final large = TextEditingValue(text: 'x' * (DocumentLimits.maxBytes + 1));
    expect(formatter.formatEditUpdate(old, large), old);
    expect(rejected, true);
    const accepted = TextEditingValue(text: 'small edit');
    expect(formatter.formatEditUpdate(old, accepted), accepted);
  });

  test(
    'local images require canonical containment; grants are session-only',
    () async {
      final directory = await Directory.systemTemp.createTemp('visor-images-');
      addTearDown(() => directory.delete(recursive: true));
      final base = await Directory('${directory.path}/docs').create();
      final outside = File('${directory.path}/outside.png');
      await outside.writeAsBytes(base64Decode(pixel));
      await File('${base.path}/inside.png').writeAsBytes(base64Decode(pixel));
      await Link('${base.path}/escape.png').create(outside.path);
      final loader = SafeImageLoader(baseDirectory: base.path);
      addTearDown(loader.dispose);
      expect(await loader.load('inside.png'), base64Decode(pixel));
      for (final source in ['../outside.png', 'escape.png', outside.path]) {
        await expectLater(
          loader.load(source),
          throwsA(isA<ImagePermissionRequired>()),
        );
      }
      loader.allow('../outside.png');
      expect(await loader.load('../outside.png'), base64Decode(pixel));
      final fresh = SafeImageLoader(baseDirectory: base.path);
      addTearDown(fresh.dispose);
      await expectLater(
        fresh.load('../outside.png'),
        throwsA(isA<ImagePermissionRequired>()),
      );
    },
  );

  test(
    'remote images need explicit permission and redirects are not followed',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/pixel');
        } else {
          request.response.add(base64Decode(pixel));
        }
        await request.response.close();
      });
      final loader = SafeImageLoader();
      addTearDown(loader.dispose);
      final url = 'http://127.0.0.1:${server.port}/pixel';
      await expectLater(
        loader.load(url),
        throwsA(isA<ImagePermissionRequired>()),
      );
      expect(requests, 0);
      loader.allow(url);
      expect(await loader.load(url), base64Decode(pixel));
      expect(await loader.load(url), base64Decode(pixel));
      expect(requests, 1);
      final redirect = 'http://127.0.0.1:${server.port}/redirect';
      loader.allow(redirect);
      await expectLater(loader.load(redirect), throwsFormatException);
      expect(requests, 2);
    },
  );

  test('image validation rejects huge dimensions and oversized payloads before rendering', () async {
    final huge = base64Decode(pixel);
    ByteData.sublistView(huge).setUint32(16, 5000);
    ByteData.sublistView(huge).setUint32(20, 5000);
    var crc = 0xffffffff;
    for (final byte in huge.sublist(12, 29)) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    ByteData.sublistView(huge).setUint32(29, crc ^ 0xffffffff);
    expect(() => SafeImageLoader.validate(huge), throwsFormatException);
    expect(
      () => SafeImageLoader.validate(Uint8List(SafeImageLoader.maxBytes + 1)),
      throwsFormatException,
    );
    // A GIF frame may declare dimensions larger than its logical canvas.
    final gif = base64Decode(
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
    );
    final frame = gif.indexOf(0x2c);
    ByteData.sublistView(gif).setUint16(frame + 5, 2000, Endian.little);
    ByteData.sublistView(gif).setUint16(frame + 7, 2000, Endian.little);
    expect(() => SafeImageLoader.validate(gif), throwsFormatException);
    final loader = SafeImageLoader();
    addTearDown(loader.dispose);
    for (var i = 0; i < 12; i++) {
      await expectLater(
        loader.load('https://example.invalid/$i'),
        throwsA(isA<ImagePermissionRequired>()),
      );
    }
    await expectLater(
      loader.load('https://example.invalid/13'),
      throwsFormatException,
    );
  });
}
