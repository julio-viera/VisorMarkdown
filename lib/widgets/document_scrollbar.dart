import 'package:flutter/material.dart';

/// Desktop scrollbar with explicit thumb gestures. Preview thumbs seek by
/// source position so a large drag doesn't lay out all intervening blocks.
class DocumentScrollbar extends RawScrollbar {
  const DocumentScrollbar({
    super.key,
    required ScrollController controller,
    required super.child,
    required this.onThumbStart,
    required this.onThumbEnd,
    this.readFraction,
    this.seek,
  }) : super(
         controller: controller,
         thumbVisibility: true,
         radius: const Radius.circular(4),
       );

  final VoidCallback onThumbStart;
  final VoidCallback onThumbEnd;
  final double Function()? readFraction;
  final ValueChanged<double>? seek;

  static Widget forDesktop(BuildContext context, DocumentScrollbar scrollbar) {
    final behavior = ScrollConfiguration.of(context);
    return switch (behavior.getPlatform(context)) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => ScrollConfiguration(
        behavior: behavior.copyWith(scrollbars: false),
        child: scrollbar,
      ),
      _ => scrollbar.child,
    };
  }

  @override
  RawScrollbarState<DocumentScrollbar> createState() =>
      _DocumentScrollbarState();
}

class _DocumentScrollbarState extends RawScrollbarState<DocumentScrollbar> {
  Offset? _start;
  double _fraction = 0;
  double _fractionPerPixel = 0;

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    if (getScrollbarDirection() != Axis.vertical) return;
    _start = localPosition;
    widget.onThumbStart();
    if (widget.readFraction case final read?) {
      final position = widget.controller!.position;
      final extent = position.maxScrollExtent - position.minScrollExtent;
      _fraction = read();
      _fractionPerPixel = extent > 0
          ? scrollbarPainter.getTrackToScroll(1) / extent
          : 0;
    }
  }

  @override
  void handleThumbPressUpdate(Offset localPosition) {
    final start = _start;
    final seek = widget.seek;
    if (start == null || seek == null) {
      super.handleThumbPressUpdate(localPosition);
      return;
    }
    // Passing the unchanged position keeps the native drag alive without
    // asking the variable-height sliver to traverse a long pixel distance.
    super.handleThumbPressUpdate(start);
    final fraction =
        _fraction + (localPosition.dy - start.dy) * _fractionPerPixel;
    if (fraction.isFinite) seek(fraction.clamp(0.0, 1.0));
  }

  void _finish() {
    if (_start == null) return;
    _start = null;
    widget.onThumbEnd();
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    _finish();
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerCancel: (_) => _finish(), child: super.build(context));

  @override
  void dispose() {
    _finish();
    super.dispose();
  }
}
