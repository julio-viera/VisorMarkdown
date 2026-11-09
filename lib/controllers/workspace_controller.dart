import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/markdown_document.dart';
import '../repositories/document_repository.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({DocumentRepository? repository, bool watch = true})
    : repository = repository ?? DocumentRepository() {
    add();
    if (watch) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => checkFiles());
    }
  }
  final DocumentRepository repository;
  final List<MarkdownDocument> documents = [];
  Timer? _timer;
  int _next = 1;
  int activeIndex = 0;
  bool _disposed = false;
  MarkdownDocument get active => documents[activeIndex];
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void add({String text = '', String? path, String? name, String? sourceId}) {
    final doc = MarkdownDocument(
      id: _next++,
      text: text,
      path: path,
      name: name,
      sourceId: sourceId,
    );
    doc.editor.addListener(changed);
    documents.add(doc);
    activeIndex = documents.length - 1;
    changed();
  }

  void select(int index) {
    activeIndex = index;
    changed();
  }

  void close(MarkdownDocument doc) {
    final index = documents.indexOf(doc);
    if (index < 0) return;
    documents.removeAt(index);
    doc.dispose();
    if (index < activeIndex) activeIndex--;
    if (activeIndex >= documents.length) activeIndex = documents.length - 1;
    if (documents.isEmpty) {
      add();
    } else {
      changed();
    }
  }

  Future<void> _openQueue = Future.value();
  Future<void> openPath(String path) {
    final request = _openQueue.then((_) => _openPath(path));
    _openQueue = request.then<void>((_) {}, onError: (Object _) {});
    return request;
  }

  Future<void> _openPath(String path) async {
    if (_disposed) return;
    final canonical = await repository.canonicalPath(path);
    if (_disposed) return;
    for (final doc in List<MarkdownDocument>.of(documents)) {
      if (doc.path == null) continue;
      final existing = await repository.canonicalPath(doc.path!);
      if (_disposed) return;
      if (repository.samePath(existing, canonical) && documents.contains(doc)) {
        select(documents.indexOf(doc));
        return;
      }
    }
    final text = await repository.read(canonical);
    if (_disposed) return;
    final blank =
        documents.length == 1 &&
            active.path == null &&
            active.editor.text.isEmpty
        ? active
        : null;
    add(text: text, path: canonical);
    if (blank != null) close(blank);
  }

  /// External Android documents are imported into a new tab. Keeping no OS
  /// path ensures Save uses the document picker instead of a private cache.
  void importDocument(OpenedFile file) {
    if (file.sourceId != null) {
      final existing = documents.indexWhere(
        (doc) => doc.sourceId == file.sourceId,
      );
      if (existing >= 0) {
        select(existing);
        return;
      }
    }
    final blank =
        documents.length == 1 &&
            active.path == null &&
            !active.dirty &&
            active.editor.text.isEmpty
        ? active
        : null;
    add(text: file.text, name: file.name, sourceId: file.sourceId);
    if (blank != null) close(blank);
  }

  /// Replaces the document in this tab after the view has resolved unsaved
  /// changes. A fresh controller also resets undo history for the new file.
  void replaceDocument(MarkdownDocument target, OpenedFile file) {
    final index = documents.indexOf(target);
    if (index < 0 || target.saving) return;
    final replacement =
        MarkdownDocument(
            id: target.id,
            text: file.text,
            path: file.path,
            name: file.name,
          )
          ..dialect = target.dialect
          ..showPreview = target.showPreview
          ..mobilePreview = target.mobilePreview;
    replacement.editorFraction.value = target.editorFraction.value;
    replacement.editor.addListener(changed);
    documents[index] = replacement;
    activeIndex = index;
    target.dispose();
    changed();
  }

  void search(String query) {
    active.query = query;
    active.editor.query = query;
    active.matchIndex = -1;
    nextMatch(1);
  }

  void nextMatch(int delta) {
    final matches = active.matches;
    if (matches.isEmpty) {
      active.matchIndex = -1;
      changed();
      return;
    }
    active.matchIndex = active.matchIndex < 0
        ? (delta < 0 ? matches.length - 1 : 0)
        : (active.matchIndex + delta) % matches.length;
    final range = matches[active.matchIndex];
    active.editor.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    changed();
  }

  Future<void> checkFiles() async {
    var modified = false;
    for (final doc in List<MarkdownDocument>.of(documents)) {
      if (doc.path == null || doc.checking || doc.saving) continue;
      doc.checking = true;
      try {
        final stamp = await repository.stamp(doc.path!);
        if (stamp != null && stamp == doc.diskStamp && !doc.missing) continue;
        final text = await repository.read(doc.path!);
        if (_disposed || !documents.contains(doc) || doc.saving) continue;
        final external = text == doc.savedText ? null : text;
        modified |= doc.missing || doc.externalText != external;
        doc.missing = false;
        doc.externalText = external;
        doc.diskStamp = stamp;
      } catch (_) {
        if (documents.contains(doc)) {
          modified |= !doc.missing;
          doc.missing = true;
          doc.diskStamp = null;
        }
      } finally {
        doc.checking = false;
      }
    }
    if (modified) changed();
  }

  void reload(MarkdownDocument doc) {
    if (doc.externalText == null) return;
    doc.savedText = doc.externalText!;
    doc.editor.text = doc.externalText!;
    doc.externalText = null;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final doc in documents) {
      doc.dispose();
    }
    super.dispose();
  }
}
