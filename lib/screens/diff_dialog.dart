import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/markdown_document.dart';
import '../models/diff_result.dart';
import '../services/diff_service.dart';
import '../l10n/strings.dart';

class DiffDialog extends StatefulWidget {
  const DiffDialog({
    super.key,
    required this.documents,
    required this.active,
    required this.strings,
  });
  final List<MarkdownDocument> documents;
  final MarkdownDocument active;
  final Strings strings;
  @override
  State<DiffDialog> createState() => _DiffDialogState();
}

class _DiffDialogState extends State<DiffDialog> {
  static const rowHeight = 28.0;
  static const codeStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.4,
  );
  late MarkdownDocument left = widget.active;
  late MarkdownDocument right = widget.documents.firstWhere((d) => d != left);
  late DiffResult result;
  final leftScroll = ScrollController();
  final rightScroll = ScrollController();
  final leftHorizontal = ScrollController();
  final rightHorizontal = ScrollController();
  bool syncing = false;
  int current = -1;
  double leftWidth = 0;
  double rightWidth = 0;

  @override
  void initState() {
    super.initState();
    recompute();
    leftScroll.addListener(() => sync(leftScroll, rightScroll));
    rightScroll.addListener(() => sync(rightScroll, leftScroll));
  }

  void sync(ScrollController source, ScrollController target) {
    if (syncing || !source.hasClients || !target.hasClients) return;
    syncing = true;
    try {
      final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
      if ((target.offset - offset).abs() > .5) target.jumpTo(offset);
    } finally {
      syncing = false;
    }
  }

  double measure(bool isLeft) {
    var width = 0.0;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );
    for (final row in result.rows) {
      painter.text = TextSpan(
        text: (isLeft ? row.left : row.right) ?? '',
        style: codeStyle,
      );
      painter.layout();
      width = math.max(width, painter.width);
    }
    painter.dispose();
    return width + 88;
  }

  void recompute() {
    result = DiffService.sideBySide(left.editor.text, right.editor.text);
    current = -1;
    leftWidth = measure(true);
    rightWidth = measure(false);
  }

  void selectDocument(bool isLeft, MarkdownDocument doc) {
    setState(() {
      if (isLeft) {
        left = doc;
      } else {
        right = doc;
      }
      recompute();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final controller in [
        leftScroll,
        rightScroll,
        leftHorizontal,
        rightHorizontal,
      ]) {
        if (controller.hasClients) controller.jumpTo(0);
      }
    });
  }

  void navigate(int direction) {
    if (result.hunks.isEmpty || !leftScroll.hasClients) return;
    setState(
      () => current = current < 0
          ? (direction > 0 ? 0 : result.hunks.length - 1)
          : (current + direction) % result.hunks.length,
    );
    final offset =
        (result.hunks[current].start * rowHeight -
                leftScroll.position.viewportDimension * .2)
            .clamp(0.0, leftScroll.position.maxScrollExtent);
    leftScroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Widget filename(bool isLeft) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<MarkdownDocument>(
        key: ValueKey(isLeft ? 'diff-left-file' : 'diff-right-file'),
        isExpanded: true,
        value: isLeft ? left : right,
        items: widget.documents
            .map(
              (d) => DropdownMenuItem(
                value: d,
                child: Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (d) {
          if (d != null) selectDocument(isLeft, d);
        },
      ),
    ),
  );

  Widget panel(bool isLeft) {
    final vertical = isLeft ? leftScroll : rightScroll;
    final horizontal = isLeft ? leftHorizontal : rightHorizontal;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          isLeft ? leftWidth : rightWidth,
        );
        return Scrollbar(
          controller: horizontal,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: vertical,
                thumbVisibility: true,
                child: ListView.builder(
                  key: ValueKey(
                    isLeft ? 'diff-left-scroll' : 'diff-right-scroll',
                  ),
                  controller: vertical,
                  itemExtent: rowHeight,
                  itemCount: result.rows.length,
                  itemBuilder: (context, index) {
                    final row = result.rows[index];
                    final text = isLeft ? row.left : row.right;
                    final number = isLeft ? row.leftLine : row.rightLine;
                    final changed = row.changed && text != null;
                    final selected =
                        current >= 0 &&
                        index >= result.hunks[current].start &&
                        index < result.hunks[current].end;
                    final tint = isLeft ? Colors.red : Colors.green;
                    final background = changed
                        ? tint.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.dark
                                ? .25
                                : .13,
                          )
                        : text == null
                        ? colors.surfaceContainer
                        : colors.surface;
                    return Container(
                      key: ValueKey(
                        'diff-${isLeft ? 'left' : 'right'}-row-$index',
                      ),
                      decoration: BoxDecoration(
                        color: background,
                        border: Border(
                          left: BorderSide(
                            width: 3,
                            color: selected
                                ? colors.primary
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SelectionContainer.disabled(
                            child: SizedBox(
                              width: 48,
                              child: Text(
                                number?.toString() ?? '',
                                textAlign: TextAlign.right,
                                style: codeStyle.copyWith(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          SelectionContainer.disabled(
                            child: SizedBox(
                              width: 24,
                              child: Text(
                                changed ? (isLeft ? '−' : '+') : '',
                                textAlign: TextAlign.center,
                                style: codeStyle.copyWith(
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: row.endOfFile
                                  ? widget.strings['eofChange']
                                  : '',
                              child: Text(
                                text ?? '',
                                maxLines: 1,
                                softWrap: false,
                                textScaler: TextScaler.noScaling,
                                style: codeStyle.copyWith(
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f7): () => navigate(1),
        const SingleActivator(LogicalKeyboardKey.f7, shift: true): () =>
            navigate(-1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: math.min(1400, size.width - 32),
            height: math.min(900, size.height - 32),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s['compareDocuments'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: s['close'],
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.hunks.isEmpty
                              ? s['identical']
                              : '${result.changedRows} ${s['differentRows']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('diff-previous'),
                        tooltip: s['previousDifference'],
                        onPressed: result.hunks.isEmpty
                            ? null
                            : () => navigate(-1),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      Text(
                        '${current + 1}/${result.hunks.length}',
                        key: const ValueKey('diff-counter'),
                      ),
                      IconButton(
                        key: const ValueKey('diff-next'),
                        tooltip: s['nextDifference'],
                        onPressed: result.hunks.isEmpty
                            ? null
                            : () => navigate(1),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),
                  Row(children: [filename(true), filename(false)]),
                  Expanded(
                    child: SelectionArea(
                      child: Row(
                        children: [
                          Expanded(child: panel(true)),
                          const VerticalDivider(width: 1),
                          Expanded(child: panel(false)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          '− ${s['removedLines']}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        Text(
                          '+ ${s['addedLines']}',
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.greenAccent
                                : Colors.green.shade800,
                          ),
                        ),
                        Text(s['originalLines']),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      leftScroll,
      rightScroll,
      leftHorizontal,
      rightHorizontal,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}
