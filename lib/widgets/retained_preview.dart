import 'package:flutter/material.dart';

import '../models/markdown_document.dart';

/// Keep at most one recent, small preview beside the active one. Large sources
/// never retain a hidden widget tree. Editors and their focus remain separate.
class RetainedPreview extends StatefulWidget {
  const RetainedPreview({
    super.key,
    required this.documents,
    required this.active,
    required this.builder,
  });
  final List<MarkdownDocument> documents;
  final MarkdownDocument active;
  final Widget Function(MarkdownDocument) builder;
  static const maxCharacters = 50000;
  @override
  State<RetainedPreview> createState() => _RetainedPreviewState();
}

class _RetainedPreviewState extends State<RetainedPreview> {
  final recent = <MarkdownDocument>[];
  final observed = <MarkdownDocument>{};

  bool get exceedsBudget =>
      recent.length > 1 &&
      recent.fold<int>(0, (sum, doc) => sum + doc.editor.text.length) >
          RetainedPreview.maxCharacters;

  void onEditorChanged() {
    if (exceedsBudget) setState(() {});
  }

  @override
  void dispose() {
    for (final doc in observed) {
      doc.editor.removeListener(onEditorChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    recent.removeWhere((doc) => !widget.documents.contains(doc));
    recent.remove(widget.active);
    recent.add(widget.active);
    while (recent.length > 2 || exceedsBudget) {
      recent.removeAt(0);
    }
    final retained = recent.toSet();
    for (final doc in observed.difference(retained)) {
      doc.editor.removeListener(onEditorChanged);
    }
    for (final doc in retained.difference(observed)) {
      doc.editor.addListener(onEditorChanged);
    }
    observed
      ..clear()
      ..addAll(retained);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final doc in recent)
          Offstage(
            key: ObjectKey(doc),
            offstage: doc != widget.active,
            child: TickerMode(
              enabled: doc == widget.active,
              child: ExcludeFocus(
                excluding: doc != widget.active,
                child: RepaintBoundary(child: widget.builder(doc)),
              ),
            ),
          ),
      ],
    );
  }
}
