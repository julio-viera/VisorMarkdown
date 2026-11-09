import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'window_chrome.dart';
import '../themes/app_theme.dart';
import '../models/markdown_document.dart';

/// The viewport scrolls independently of the actions pinned to its right.
class DocumentTabStrip extends StatefulWidget {
  const DocumentTabStrip({
    super.key,
    required this.documents,
    required this.activeIndex,
    required this.strings,
    required this.onSelect,
    required this.onClose,
    required this.actions,
    this.draggableBackground = false,
  });
  final List<MarkdownDocument> documents;
  final int activeIndex;
  final Strings strings;
  final ValueChanged<int> onSelect;
  final ValueChanged<MarkdownDocument> onClose;
  final List<Widget> actions;
  final bool draggableBackground;

  @override
  State<DocumentTabStrip> createState() => _DocumentTabStripState();
}

class _DocumentTabStripState extends State<DocumentTabStrip> {
  static const minimumExtent = 190.0;
  static const overlap = 14.0;
  final measuredTitles = <int, (String, double)>{};
  TextStyle? measuredStyle;
  TextScaler? measuredScaler;
  TextDirection? measuredDirection;
  Locale? measuredLocale;
  List<double> extents = [];
  List<double> starts = [];
  bool revealPending = false;
  final scroll = ScrollController();
  bool canBack = false;
  bool canForward = false;
  double? lastViewport;

  @override
  void initState() {
    super.initState();
    scroll.addListener(updateArrows);
    revealActive();
  }

  @override
  void didUpdateWidget(DocumentTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.documents.length != widget.documents.length) {
      revealActive();
    }
  }

  void updateGeometry(BuildContext context, double available) {
    // Reserve bold text and the dirty marker so selection/typing cannot make
    // tabs jump in width. Cache text measurement independently of window size.
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontWeight: FontWeight.bold);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    if (style != measuredStyle ||
        scaler != measuredScaler ||
        direction != measuredDirection ||
        locale != measuredLocale) {
      measuredTitles.clear();
      measuredStyle = style;
      measuredScaler = scaler;
      measuredDirection = direction;
      measuredLocale = locale;
    }
    final ids = widget.documents.map((doc) => doc.id).toSet();
    measuredTitles.removeWhere((id, _) => !ids.contains(id));
    final natural = <double>[];
    for (final doc in widget.documents) {
      var measurement = measuredTitles[doc.id];
      if (measurement == null || measurement.$1 != doc.title) {
        final painter = TextPainter(
          text: TextSpan(text: '• ${doc.title}', style: style),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
        )..layout();
        measurement = (doc.title, painter.width);
        measuredTitles[doc.id] = measurement;
        painter.dispose();
      }
      // Text plus padding, close control and space between title and control.
      natural.add((measurement.$2 + 56).clamp(minimumExtent, double.infinity));
    }
    final usable = (available - overlap).clamp(0.0, double.infinity);
    final minimumTotal = minimumExtent * natural.length;
    final naturalTotal = natural.fold<double>(0, (sum, width) => sum + width);
    final factor = usable < minimumTotal
        ? 0.0
        : naturalTotal <= usable
        ? 1.0
        : (usable - minimumTotal) / (naturalTotal - minimumTotal);
    final widths = natural
        .map((width) => minimumExtent + (width - minimumExtent) * factor)
        .toList();
    var changed = widths.length != extents.length;
    if (!changed) {
      for (var i = 0; i < widths.length; i++) {
        if ((widths[i] - extents[i]).abs() > .01) {
          changed = true;
          break;
        }
      }
    }
    extents = widths;
    starts = [];
    var offset = 0.0;
    for (final width in widths) {
      starts.add(offset);
      offset += width;
    }
    if (changed) revealActive();
  }

  void updateArrows() {
    if (!mounted || !scroll.hasClients) return;
    final back = scroll.offset > .5;
    final forward = scroll.offset < scroll.position.maxScrollExtent - .5;
    if (back != canBack || forward != canForward) {
      setState(() {
        canBack = back;
        canForward = forward;
      });
    }
  }

  void revealActive() {
    if (revealPending) return;
    revealPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      revealPending = false;
      if (!mounted ||
          !scroll.hasClients ||
          widget.activeIndex < 0 ||
          widget.activeIndex >= extents.length) {
        return;
      }
      final start = starts[widget.activeIndex];
      final end = start + extents[widget.activeIndex] + overlap;
      final viewport = scroll.position.viewportDimension;
      var offset = scroll.offset;
      if (start < offset) offset = start;
      if (end > offset + viewport) offset = end - viewport;
      offset = offset.clamp(0, scroll.position.maxScrollExtent);
      if ((offset - scroll.offset).abs() > .5) scroll.jumpTo(offset);
      updateArrows();
    });
  }

  void page(int direction) => scroll.animateTo(
    (scroll.offset + direction * scroll.position.viewportDimension * .8).clamp(
      0,
      scroll.position.maxScrollExtent,
    ),
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
  );

  Widget arrow(String key, String label, IconData icon, VoidCallback? action) =>
      IconButton(
        key: ValueKey(key),
        tooltip: label,
        onPressed: action,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 36),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Row(
      children: [
        arrow(
          'tabs-back',
          widget.strings['tabsBack'],
          Icons.chevron_left,
          canBack ? () => page(-1) : null,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              updateGeometry(context, constraints.maxWidth);
              return NotificationListener<ScrollMetricsNotification>(
                onNotification: (notification) {
                  if (lastViewport != notification.metrics.viewportDimension) {
                    lastViewport = notification.metrics.viewportDimension;
                    revealActive();
                  }
                  return false;
                },
                child: WindowDragRegion(
                  enabled: widget.draggableBackground,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Scrollbar(
                      controller: scroll,
                      thumbVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.top,
                      thickness: 3,
                      child: ListView.builder(
                        key: const ValueKey('tabs-scroll'),
                        controller: scroll,
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        itemExtentBuilder: (index, _) =>
                            index < extents.length ? extents[index] : null,
                        padding: const EdgeInsets.only(right: overlap),
                        itemCount: widget.documents.length,
                        itemBuilder: (context, index) {
                          final doc = widget.documents[index];
                          final selected = index == widget.activeIndex;
                          final colors = Theme.of(context).colorScheme;
                          final chrome = DocumentChromeColors(colors);
                          return OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: extents[index] + overlap,
                            maxWidth: extents[index] + overlap,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
                              child: Material(
                                color: selected
                                    ? chrome.active
                                    : chrome.inactive,
                                shape: const CurvedTabShape(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  key: ValueKey('tab-${doc.id}'),
                                  customBorder: const CurvedTabShape(),
                                  onTap: () => widget.onSelect(index),
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 8,
                                      right: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '${doc.dirty ? '• ' : ''}${doc.title}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color: selected
                                                      ? colors.primary
                                                      : colors.onSurface,
                                                  fontWeight: selected
                                                      ? FontWeight.bold
                                                      : null,
                                                ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: widget.strings['close'],
                                          onPressed: doc.saving
                                              ? null
                                              : () => widget.onClose(doc),
                                          color: selected
                                              ? colors.primary
                                              : colors.onSurface,
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                width: 30,
                                                height: 32,
                                              ),
                                          style: IconButton.styleFrom(
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        arrow(
          'tabs-forward',
          widget.strings['tabsForward'],
          Icons.chevron_right,
          canForward ? () => page(1) : null,
        ),
        ...widget.actions,
        const SizedBox(width: 4),
      ],
    ),
  );

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }
}

/// Asymmetric lower flares overlap decoratively while the tab body and close
/// button remain inside their own scroll item's hit-test bounds.
class CurvedTabShape extends ShapeBorder {
  const CurvedTabShape();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final w = rect.width, h = rect.height;
    final leftFlare = 8.0.clamp(0.0, h / 3);
    final rightFlare = 12.0.clamp(0.0, h / 3);
    final radius = 10.0.clamp(0.0, h / 3);
    return (Path()
          ..moveTo(0, h)
          ..quadraticBezierTo(leftFlare, h, leftFlare, h - leftFlare)
          ..lineTo(leftFlare, radius)
          ..quadraticBezierTo(leftFlare, 0, leftFlare + radius, 0)
          ..lineTo(w - rightFlare - radius, 0)
          ..quadraticBezierTo(w - rightFlare, 0, w - rightFlare, radius)
          ..lineTo(w - rightFlare, h - rightFlare)
          ..quadraticBezierTo(w - rightFlare, h, w, h)
          ..close())
        .shift(rect.topLeft);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}
