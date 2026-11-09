import 'package:flutter/widgets.dart';

/// Synchronizes the top of each panel using a character offset in the source.
class SynchronizedScrollControllers {
  SynchronizedScrollControllers() {
    editor = ScrollController(
      onAttach: (_) {
        _restoringEditor = true;
        _schedule();
      },
    );
    preview = ScrollController(onAttach: (_) => _schedule());
    editor.addListener(() => _scrolled(fromPreview: false));
    preview.addListener(() => _scrolled(fromPreview: true));
  }

  late final ScrollController editor;
  late final ScrollController preview;
  int? Function()? readEditor;
  void Function(int)? revealEditor;
  int? Function()? readPreview;
  void Function(int)? revealPreview;

  int _anchor = 0;
  bool? _fromPreview;
  bool _restoringEditor = false;
  bool _syncing = false;
  bool _scheduled = false;
  bool _disposed = false;

  void _scrolled({required bool fromPreview}) {
    if (_disposed || _syncing) return;
    final source = fromPreview ? preview : editor;
    if (source.positions.length != 1 ||
        !source.position.hasContentDimensions ||
        source.position.maxScrollExtent <= source.position.minScrollExtent) {
      return;
    }
    _fromPreview = fromPreview;
    _schedule();
  }

  void _schedule() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      // A preview mounted in the same frame may ask to read the editor
      // before its viewport has recovered this tab's saved source position.
      final fromPreview = _restoringEditor ? null : _fromPreview;
      _restoringEditor = false;
      _fromPreview = null;
      final anchor = switch (fromPreview) {
        true => readPreview?.call(),
        false => readEditor?.call() ?? _anchor,
        null => _anchor,
      };
      if (anchor == null) return;
      _anchor = anchor;
      _syncing = true;
      try {
        if (fromPreview != true) revealPreview?.call(_anchor);
        if (fromPreview != false) revealEditor?.call(_anchor);
      } finally {
        _syncing = false;
      }
    });
    binding.ensureVisualUpdate();
  }

  void previewChanged() {
    _fromPreview ??= false;
    _schedule();
  }

  void dispose() {
    _disposed = true;
    editor.dispose();
    preview.dispose();
  }
}
