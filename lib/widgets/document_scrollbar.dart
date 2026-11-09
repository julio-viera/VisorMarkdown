import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Editor scrollbar that lets the preview synchronize when the thumb is released.
class DocumentScrollbar extends RawScrollbar {
  const DocumentScrollbar({
    super.key,
    required ScrollController controller,
    required super.child,
    required this.onThumbStart,
    required this.onThumbEnd,
  }) : super(
         controller: controller,
         thumbVisibility: true,
         thickness: 14,
         minThumbLength: 36,
         radius: const Radius.circular(4),
       );

  final VoidCallback onThumbStart;
  final VoidCallback onThumbEnd;

  static Widget forDesktop(BuildContext context, DocumentScrollbar scrollbar) {
    final behavior = ScrollConfiguration.of(context);
    return switch (behavior.getPlatform(context)) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => ScrollConfiguration(
        behavior: const _DocumentScrollBehavior(),
        child: scrollbar,
      ),
      _ => scrollbar.child,
    };
  }

  @override
  RawScrollbarState<DocumentScrollbar> createState() =>
      _DocumentScrollbarState();
}

// EditableText explicitly enables automatic scrollbars for multiline fields
// when copying the inherited behavior. Override decoration at its source.
class _DocumentScrollBehavior extends MaterialScrollBehavior {
  const _DocumentScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _DocumentScrollbarState extends RawScrollbarState<DocumentScrollbar> {
  bool _dragging = false;
  bool _hoveringThumb = false;

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    if (getScrollbarDirection() != Axis.vertical) return;
    setState(() => _dragging = true);
    widget.onThumbStart();
  }

  void _finish() {
    if (!_dragging) return;
    _dragging = false;
    widget.onThumbEnd();
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    _finish();
    if (mounted) setState(() {});
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final hovering = isPointerOverThumb(event.position, event.kind);
    if (_hoveringThumb != hovering) setState(() => _hoveringThumb = hovering);
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (_hoveringThumb) setState(() => _hoveringThumb = false);
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    final colors = Theme.of(context).colorScheme;
    scrollbarPainter.color = _hoveringThumb || _dragging
        ? colors.onSurfaceVariant
        : colors.outline;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _dragging
        ? SystemMouseCursors.grabbing
        : _hoveringThumb
        ? SystemMouseCursors.grab
        : MouseCursor.defer,
    child: Listener(
      onPointerCancel: (_) {
        _finish();
        setState(() => _hoveringThumb = false);
      },
      child: super.build(context),
    ),
  );

  @override
  void dispose() {
    _finish();
    super.dispose();
  }
}
