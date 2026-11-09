import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DocumentSplitView extends StatefulWidget {
  const DocumentSplitView({
    super.key,
    required this.editor,
    required this.editorFraction,
    required this.preview,
    required this.dividerLabel,
    required this.onResizeEnd,
  });

  final Widget editor;
  final ValueNotifier<double> editorFraction;
  final Widget? preview;
  final String dividerLabel;
  final VoidCallback onResizeEnd;

  @override
  State<DocumentSplitView> createState() => _DocumentSplitViewState();
}

class _DocumentSplitViewState extends State<DocumentSplitView> {
  static const _dividerWidth = 12.0;
  static const _minimumPanelWidth = 240.0;
  bool _dividerFocused = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.editorFraction,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _dividerWidth;
        final minimum = available < _minimumPanelWidth * 2
            ? available / 2
            : _minimumPanelWidth;
        final editorWidth = (available * widget.editorFraction.value).clamp(
          minimum,
          available - minimum,
        );
        final direction = Directionality.of(context) == TextDirection.rtl
            ? -1
            : 1;
        final colors = Theme.of(context).colorScheme;
        void resize(double delta, {bool dragging = false}) {
          final width = (available * widget.editorFraction.value).clamp(
            minimum,
            available - minimum,
          );
          final next = (width + delta).clamp(minimum, available - minimum);
          if (next == width) return;
          widget.editorFraction.value = next / available;
          if (!dragging) widget.onResizeEnd();
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: widget.preview == null
                  ? constraints.maxWidth
                  : editorWidth,
              child: widget.editor,
            ),
            if (widget.preview case final preview?) ...[
              SizedBox(
                key: const ValueKey('preview-divider'),
                width: _dividerWidth,
                child: Semantics(
                  label: widget.dividerLabel,
                  onIncrease: () => resize(24),
                  onDecrease: () => resize(-24),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                          resize(-24.0 * direction),
                      const SingleActivator(
                        LogicalKeyboardKey.arrowRight,
                      ): () =>
                          resize(24.0 * direction),
                    },
                    child: Focus(
                      onFocusChange: (focused) =>
                          setState(() => _dividerFocused = focused),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (event) => resize(
                            event.delta.dx * direction,
                            dragging: true,
                          ),
                          onHorizontalDragEnd: (_) => widget.onResizeEnd(),
                          onHorizontalDragCancel: widget.onResizeEnd,
                          child: ColoredBox(
                            color: colors.surfaceContainer,
                            child: Center(
                              child: Container(
                                width: _dividerFocused ? 4 : 3,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _dividerFocused
                                      ? colors.primary
                                      : colors.outline,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: preview),
            ],
          ],
        );
      },
    ),
  );
}
