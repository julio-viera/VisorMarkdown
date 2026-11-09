import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../widgets/search_editor_controller.dart';
import '../services/safe_image_loader.dart';
import '../controllers/synchronized_scroll_controllers.dart';

enum MarkdownDialect {
  original,
  commonMark,
  gfm;

  bool get supportsTables => this == MarkdownDialect.gfm;

  String get label => switch (this) {
    original => 'Markdown Original',
    commonMark => 'CommonMark',
    gfm => 'GitHub Flavored Markdown',
  };
  md.ExtensionSet get extensions => switch (this) {
    original => md.ExtensionSet.none,
    commonMark => md.ExtensionSet.commonMark,
    gfm => md.ExtensionSet.gitHubFlavored,
  };
}

class MarkdownDocument {
  MarkdownDocument({
    required this.id,
    String text = '',
    this.path,
    String? name,
    this.sourceId,
  }) : editor = SearchEditorController(text: text),
       savedText = text,
       originalName = name;
  final int id;
  final SearchEditorController editor;
  bool showPreview = true;
  bool mobilePreview = false;
  final editorFraction = ValueNotifier(.5);
  final scrollSync = SynchronizedScrollControllers();
  ScrollController get scroll => scrollSync.editor;
  ScrollController get previewScroll => scrollSync.preview;
  String? path;
  final String? originalName;
  final String? sourceId;
  String savedText;
  MarkdownDialect dialect = MarkdownDialect.gfm;
  String query = '';
  int matchIndex = -1;
  String? externalText;
  bool missing = false;
  bool checking = false;
  bool saving = false;
  bool get dirty => editor.text != savedText;
  String get title =>
      path != null ? p.basename(path!) : originalName ?? 'Untitled $id';
  String? diskStamp;
  SafeImageLoader? _images;
  SafeImageLoader get images {
    final base = path == null ? null : p.dirname(path!);
    if (_images == null || _images!.baseDirectory != base) {
      _images?.dispose();
      _images = SafeImageLoader(baseDirectory: base);
    }
    return _images!;
  }

  List<TextRange> get matches => editor.matchesFor(query);

  void dispose() {
    _images?.dispose();
    editor.dispose();
    scrollSync.dispose();
    editorFraction.dispose();
  }
}
