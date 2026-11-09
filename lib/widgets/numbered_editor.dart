import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../services/document_limits.dart';
import '../themes/app_theme.dart';

/// Keeps the native TextField (selection, IME, undo and search) and derives
/// the gutter from its actual layout rather than estimating line heights.
class NumberedEditor extends StatefulWidget {
  const NumberedEditor({
    super.key,
    required this.controller,
    required this.scroll,
    required this.focusNode,
    required this.style,
    required this.fieldKey,
    this.onLimitExceeded,
  });
  final TextEditingController controller;
  final ScrollController scroll;
  final FocusNode focusNode;
  final TextStyle style;
  final Key fieldKey;
  final VoidCallback? onLimitExceeded;

  @override
  State<NumberedEditor> createState() => _NumberedEditorState();
}

class _NumberedEditorState extends State<NumberedEditor> {
  final gutterKey = GlobalKey();
  String? cachedText;
  List<int> starts = [0];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(textChanged);
  }

  void textChanged() {
    if (widget.controller.text != cachedText) setState(() {});
  }

  @override
  void didUpdateWidget(NumberedEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(textChanged);
      widget.controller.addListener(textChanged);
      cachedText = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(textChanged);
    super.dispose();
  }

  List<int> lineStarts() {
    final text = widget.controller.text;
    if (text != cachedText) {
      cachedText = text;
      starts = [0, ...RegExp(r'\r\n|\r|\n').allMatches(text).map((m) => m.end)];
    }
    return starts;
  }

  EditableTextState? editableState() =>
      widget.focusNode.context?.findAncestorStateOfType<EditableTextState>();

  void insertIndent() {
    final value = widget.controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final replacement = value.copyWith(
      text: value.text.replaceRange(selection.start, selection.end, '    '),
      selection: TextSelection.collapsed(offset: selection.start + 4),
      composing: TextRange.empty,
    );
    // Use the native editing path to retain formatters, undo and caret scrolling.
    editableState()?.userUpdateTextEditingValue(
      replacement,
      SelectionChangedCause.keyboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final offsets = lineStarts();
    final colors = Theme.of(context).colorScheme;
    final editorColors = EditorColors(Theme.of(context).brightness);
    final scaler = MediaQuery.textScalerOf(context);
    final measure = TextPainter(
      text: TextSpan(
        text: '9' * offsets.length.toString().length,
        style: widget.style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = math.max(40.0, measure.width + 20);
    measure.dispose();
    return ColoredBox(
      key: const ValueKey('editor-surface'),
      color: editorColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: width,
            child: ColoredBox(
              color: editorColors.gutter,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ClipRect(
                    child: CustomPaint(
                      key: gutterKey,
                      painter: LineNumberPainter(
                        controller: widget.controller,
                        scroll: widget.scroll,
                        offsets: offsets,
                        style: widget.style.copyWith(
                          color: editorColors.lineNumber,
                        ),
                        editable: editableState,
                        gutter: () =>
                            gutterKey.currentContext?.findRenderObject()
                                as RenderBox?,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.tab): insertIndent,
              },
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                inputFormatters: [
                  DocumentInputFormatter(widget.onLimitExceeded),
                ],
                focusNode: widget.focusNode,
                scrollController: widget.scroll,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: editorColors.foreground,
                style: widget.style.copyWith(color: editorColors.foreground),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LineNumberPlacement {
  const LineNumberPlacement(this.number, this.top, this.baseline, this.height);
  final int number;
  final double top;
  final double baseline;
  final double height;
}

class LineNumberPainter extends CustomPainter {
  LineNumberPainter({
    required this.controller,
    required ScrollController scroll,
    required this.offsets,
    required this.style,
    required this.editable,
    required this.gutter,
  }) : super(repaint: Listenable.merge([controller, scroll]));
  final TextEditingController controller;
  final List<int> offsets;
  final TextStyle style;
  final EditableTextState? Function() editable;
  final RenderBox? Function() gutter;

  TextPainter numberPainter(RenderEditable render, String number) =>
      TextPainter(
        text: TextSpan(text: number, style: style),
        textDirection: TextDirection.ltr,
        textScaler: render.textScaler,
        strutStyle: render.strutStyle,
        textHeightBehavior: render.textHeightBehavior,
        maxLines: 1,
      )..layout();

  /// Visible logical lines only. Wrapped continuations do not get a new number.
  /// The caret endpoint includes the editor's scroll offset and text padding.
  List<LineNumberPlacement> layoutNumbers(Size size) {
    final placements = <LineNumberPlacement>[];
    _layoutNumbers(size, (placement, _) => placements.add(placement));
    return placements;
  }

  void _layoutNumbers(
    Size size,
    void Function(LineNumberPlacement, TextPainter) visit,
  ) {
    final state = editable();
    final box = gutter();
    if (state == null ||
        box == null ||
        !box.hasSize ||
        state.widget.controller != controller) {
      return;
    }
    final render = state.renderEditable;
    if (!render.attached || !render.hasSize) return;
    final topPosition = render
        .getPositionForPoint(render.localToGlobal(Offset.zero))
        .offset;
    var low = 0;
    var high = offsets.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (offsets[middle] <= topPosition) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final origin = box.localToGlobal(Offset.zero);
    for (var index = math.max(0, low - 1); index < offsets.length; index++) {
      final endpoint = render
          .getEndpointsForSelection(
            TextSelection.collapsed(offset: offsets[index]),
          )
          .first
          .point;
      final textTop =
          render
              .localToGlobal(
                Offset(0, endpoint.dy - render.preferredLineHeight),
              )
              .dy -
          origin.dy;
      final painter = numberPainter(render, '${index + 1}');
      final top =
          textTop -
          painter
              .getOffsetForCaret(const TextPosition(offset: 0), Rect.zero)
              .dy;
      final height = painter.height;
      final baseline =
          top +
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      if (top <= size.height && top + height >= 0) {
        visit(LineNumberPlacement(index + 1, top, baseline, height), painter);
      }
      painter.dispose();
      if (top > size.height) break;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _layoutNumbers(size, (placement, painter) {
      painter.paint(
        canvas,
        Offset(size.width - painter.width - 10, placement.top),
      );
    });
  }

  @override
  bool shouldRepaint(covariant LineNumberPainter oldDelegate) => true;
}

/// Reject the whole edit so selections and existing text remain intact.
class DocumentInputFormatter extends TextInputFormatter {
  DocumentInputFormatter([this.onRejected]);
  final VoidCallback? onRejected;
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == oldValue.text) return newValue;
    try {
      DocumentLimits.validate(newValue.text);
      return newValue;
    } on FormatException {
      onRejected?.call();
      return oldValue;
    }
  }
}
