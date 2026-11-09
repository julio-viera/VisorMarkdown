import 'dart:async';

import 'package:flutter/widgets.dart';

/// Groups edits to long documents while bounding the delay during sustained
/// typing. Opening a document still publishes its initial text immediately.
class DeferredDocumentText extends StatefulWidget {
  const DeferredDocumentText({
    super.key,
    required this.controller,
    required this.builder,
  });

  final TextEditingController controller;
  final Widget Function(String) builder;

  @override
  State<DeferredDocumentText> createState() => _DeferredDocumentTextState();
}

class _DeferredDocumentTextState extends State<DeferredDocumentText> {
  static const _largeDocument = 16 * 1024;
  static const _idleDelay = Duration(milliseconds: 180);
  static const _maxDelay = Duration(milliseconds: 650);

  late String _published;
  late String _latest;
  Timer? _idle;
  Timer? _deadline;

  @override
  void initState() {
    super.initState();
    _published = _latest = widget.controller.text;
    widget.controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(DeferredDocumentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_textChanged);
    _cancelTimers();
    _published = _latest = widget.controller.text;
    widget.controller.addListener(_textChanged);
  }

  void _textChanged() {
    final text = widget.controller.text;
    if (text == _latest) return;
    _latest = text;
    if (text == _published || text.length < _largeDocument) {
      _publish();
      return;
    }
    _idle?.cancel();
    _idle = Timer(_idleDelay, _publish);
    _deadline ??= Timer(_maxDelay, _publish);
  }

  void _cancelTimers() {
    _idle?.cancel();
    _idle = null;
    _deadline?.cancel();
    _deadline = null;
  }

  void _publish() {
    _cancelTimers();
    if (_published != _latest) setState(() => _published = _latest);
  }

  @override
  Widget build(BuildContext context) => widget.builder(_published);

  @override
  void dispose() {
    _cancelTimers();
    widget.controller.removeListener(_textChanged);
    super.dispose();
  }
}
