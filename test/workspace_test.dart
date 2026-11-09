import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/repositories/document_repository.dart';

class MemoryRepository extends DocumentRepository {
  @override
  Future<String> canonicalPath(String path) async => path;
  final files = <String, String>{};
  @override
  Future<String> read(String path) async {
    if (!files.containsKey(path)) throw const FileSystemException('missing');
    return files[path]!;
  }
}

void main() {
  test('only dirty transitions notify the workspace during local edits', () {
    final c = WorkspaceController(watch: false);
    addTearDown(c.dispose);
    final editor = c.active.editor;
    var notifications = 0;
    c.addListener(() => notifications++);

    editor.text = 'one';
    expect(notifications, 1);
    editor.selection = const TextSelection.collapsed(offset: 1);
    editor.text = 'two';
    expect(notifications, 1);

    c.active.savedText = 'two';
    c.changed();
    editor.text = 'three';
    expect(notifications, 3);
    editor.text = 'two';
    expect(notifications, 4);
  });

  test(
    'tabs isolate search, support literal Unicode and wrap in either direction',
    () {
      final c = WorkspaceController(watch: false);
      addTearDown(c.dispose);
      c.active.editor.text = 'Árbol [x] [X]';
      c.search('[x]');
      expect(c.active.matches.length, 2);
      expect(c.active.editor.selection.start, 6);
      c.nextMatch(-1);
      expect(c.active.editor.selection.start, 10);
      c.add(text: 'other');
      expect(c.active.query, isEmpty);
      c.select(0);
      expect(c.active.query, '[x]');
      c.active.editor.text = '';
      c.nextMatch(1);
      expect(c.active.matchIndex, -1);
    },
  );
  test(
    'opening replaces blank tab and closing preserves a usable document',
    () async {
      final repo = MemoryRepository()..files['/one.md'] = '# One';
      final c = WorkspaceController(repository: repo, watch: false);
      addTearDown(c.dispose);
      await c.openPath('/one.md');
      expect(c.documents.length, 1);
      expect(c.active.dirty, false);
      await c.openPath('/one.md');
      expect(c.documents.length, 1);
      c.close(c.active);
      expect(c.documents.length, 1);
      expect(c.active.editor.text, isEmpty);
      expect(c.active.dialect, MarkdownDialect.gfm);
    },
  );
  test(
    'external changes and deletion preserve local text until explicit reload',
    () async {
      final repo = MemoryRepository()..files['/one.md'] = 'initial';
      final c = WorkspaceController(repository: repo, watch: false);
      addTearDown(c.dispose);
      await c.openPath('/one.md');
      c.active.editor.text = 'local';
      repo.files['/one.md'] = 'external';
      await c.checkFiles();
      expect(c.active.externalText, 'external');
      expect(c.active.editor.text, 'local');
      c.reload(c.active);
      expect(c.active.editor.text, 'external');
      expect(c.active.dirty, false);
      repo.files.remove('/one.md');
      await c.checkFiles();
      expect(c.active.missing, true);
      expect(c.active.editor.text, 'external');
    },
  );
}
