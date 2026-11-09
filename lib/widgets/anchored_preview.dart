import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../controllers/synchronized_scroll_controllers.dart';
import '../models/markdown_document.dart';
import 'blank_line_preview.dart';
import 'preview_source.dart';

class AnchoredPreview extends StatefulWidget {
  const AnchoredPreview({
    super.key,
    required this.data,
    required this.editor,
    required this.dialect,
    required this.scrollSync,
    required this.styleSheet,
    required this.blankLineHeight,
    required this.imageBuilder,
    required this.onTapLink,
  });

  final String data;
  final TextEditingController editor;
  final MarkdownDialect dialect;
  final SynchronizedScrollControllers scrollSync;
  final MarkdownStyleSheet styleSheet;
  final double blankLineHeight;
  final MarkdownImageBuilder imageBuilder;
  final MarkdownTapLinkCallback onTapLink;

  @override
  State<AnchoredPreview> createState() => _AnchoredPreviewState();
}

class _AnchoredPreviewState extends State<AnchoredPreview> {
  final _viewport = GlobalKey();
  final _before = GlobalKey();
  final _after = GlobalKey();
  List<PreviewBlock> _blocks = const [];
  String? _parsedData;
  MarkdownDialect? _parsedDialect;
  bool _parsing = false;
  static const _backgroundParseThreshold = 64 * 1024;
  int _center = 0;
  double? _viewportHeight;

  @override
  void initState() {
    super.initState();
    _parse();
    widget.scrollSync.readPreview = _read;
    widget.scrollSync.revealPreview = _reveal;
  }

  @override
  void didUpdateWidget(AnchoredPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data || oldWidget.dialect != widget.dialect) {
      _parse();
    } else if (oldWidget.styleSheet != widget.styleSheet ||
        oldWidget.blankLineHeight != widget.blankLineHeight) {
      widget.scrollSync.previewChanged();
    }
  }

  void _parse() {
    final data = widget.data;
    final dialect = widget.dialect;
    if (data.length < _backgroundParseThreshold) {
      _applyBlocks(data, dialect, parsePreview(data, dialect.extensions));
    } else if (!_parsing) {
      unawaited(_parseInBackground(data, dialect));
    }
  }

  Future<void> _parseInBackground(String data, MarkdownDialect dialect) async {
    _parsing = true;
    try {
      final blocks = await compute(_parseDocument, (
        data,
        dialect,
      ), debugLabel: 'Markdown preview');
      if (mounted && widget.data == data && widget.dialect == dialect) {
        setState(() => _applyBlocks(data, dialect, blocks));
      }
    } catch (error, stack) {
      if (mounted && widget.data == data && widget.dialect == dialect) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            context: ErrorDescription('while parsing the Markdown preview'),
          ),
        );
      }
    } finally {
      _parsing = false;
      // Keep at most one active job and coalesce edits into the latest source.
      if (mounted &&
          (widget.data != data || widget.dialect != dialect) &&
          !_hasCurrentBlocks) {
        _parse();
      }
    }
  }

  bool get _hasCurrentBlocks =>
      _parsedData == widget.data && _parsedDialect == widget.dialect;

  void _applyBlocks(
    String data,
    MarkdownDialect dialect,
    List<PreviewBlock> blocks,
  ) {
    _blocks = blocks;
    _parsedData = data;
    _parsedDialect = dialect;
    _center = _center.clamp(0, _blocks.isEmpty ? 0 : _blocks.length - 1);
    widget.scrollSync.previewChanged();
  }

  @override
  void dispose() {
    final sync = widget.scrollSync;
    if (sync.readPreview == _read) {
      sync.readPreview = null;
      sync.revealPreview = null;
    }
    super.dispose();
  }

  Iterable<(int, RenderBox)> _mountedBlocks() sync* {
    for (final (key, reverse) in [(_before, true), (_after, false)]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) {
        continue;
      }
      for (
        var child = sliver.firstChild;
        child != null;
        child = sliver.childAfter(child)
      ) {
        final index = sliver.indexOf(child);
        final block = reverse ? _center - 1 - index : _center + index;
        if (block >= 0 && block < _blocks.length && child.hasSize) {
          yield (block, child);
        }
      }
    }
  }

  int? _read() {
    if (!_hasCurrentBlocks || widget.editor.text != widget.data) return null;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return null;
    (int, double, double)? first;
    for (final (index, box) in _mountedBlocks()) {
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final height = box.size.height;

      if (height > 0 && top + height > 0 && (first == null || top < first.$2)) {
        first = (index, top, height);
      }
    }
    if (first == null) return null;
    final (index, top, height) = first;
    final range = _blocks[index].source;
    final padding = index == 0 ? 16 : 0;
    final fraction = height <= padding
        ? 0.0
        : ((-top - padding) / (height - padding)).clamp(0.0, 1.0);
    return range.start + ((range.end - range.start) * fraction).floor();
  }

  void _reveal(int offset) {
    if (_blocks.isEmpty ||
        !_hasCurrentBlocks ||
        widget.editor.text != widget.data) {
      return;
    }
    final controller = widget.scrollSync.preview;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (!controller.hasClients || viewport == null) return;

    var low = 0;
    var high = _blocks.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_blocks[middle].source.start <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = (low - 1).clamp(0, _blocks.length - 1);
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    for (final (mounted, box) in _mountedBlocks()) {
      if (mounted != index) continue;
      final range = _blocks[index].source;
      final fraction = range.end == range.start
          ? 0.0
          : ((offset - range.start) / (range.end - range.start)).clamp(
              0.0,
              1.0,
            );
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final padding = index == 0 && fraction > 0 ? 16 : 0;
      final target =
          (position.pixels +
                  top +
                  padding +
                  fraction * (box.size.height - padding))
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() > .5) controller.jumpTo(target);
      return;
    }

    // Change the viewport origin for distant jumps. Flutter can lay out the
    // destination directly without creating the intervening blocks.
    if (_center != index) {
      controller.jumpTo(0);
      setState(() => _center = index);
      widget.scrollSync.previewChanged();
    }
  }

  Widget _block(BuildContext context, int index) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      index == 0 ? 16 : 0,
      16,
      index == _blocks.length - 1 ? 16 : 0,
    ),
    child: _RenderedBlock(node: _blocks[index].node, preview: widget),
  );

  @override
  Widget build(BuildContext context) => ClipRect(
    key: _viewport,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        final height = notification.metrics.viewportDimension;
        if (notification.depth == 0 && _viewportHeight != height) {
          _viewportHeight = height;
          widget.scrollSync.previewChanged();
        }
        return false;
      },
      child: CustomScrollView(
        controller: widget.scrollSync.preview,
        center: _after,
        slivers: [
          SliverList.builder(
            key: _before,
            itemCount: _center,
            itemBuilder: (context, index) =>
                _block(context, _center - 1 - index),
          ),
          SliverList.builder(
            key: _after,
            itemCount: _blocks.length - _center,
            itemBuilder: (context, index) => _block(context, _center + index),
          ),
        ],
      ),
    ),
  );
}

List<PreviewBlock> _parseDocument((String, MarkdownDialect) request) =>
    parsePreview(request.$1, request.$2.extensions);

class _RenderedBlock extends StatefulWidget {
  const _RenderedBlock({required this.node, required this.preview});
  final md.Node node;
  final AnchoredPreview preview;

  @override
  State<_RenderedBlock> createState() => _RenderedBlockState();
}

class _RenderedBlockState extends State<_RenderedBlock>
    implements MarkdownBuilderDelegate {
  final _links = <TapGestureRecognizer>[];
  Widget? _rendered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rendered = null;
  }

  @override
  void didUpdateWidget(_RenderedBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.node, widget.node) ||
        oldWidget.preview.styleSheet != widget.preview.styleSheet ||
        oldWidget.preview.blankLineHeight != widget.preview.blankLineHeight) {
      _rendered = null;
    }
  }

  void _disposeLinks() {
    for (final link in _links) {
      link.dispose();
    }
    _links.clear();
  }

  @override
  void dispose() {
    _disposeLinks();
    super.dispose();
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.preview.onTapLink(text, href, title);
    _links.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) => TextSpan(
    style: styleSheet.code,
    text: code.endsWith('\n') ? code.substring(0, code.length - 1) : code,
  );

  @override
  Widget build(BuildContext context) {
    if (_rendered case final rendered?) return rendered;
    _disposeLinks();
    final children = MarkdownBuilder(
      delegate: this,
      selectable: true,
      styleSheet: widget.preview.styleSheet,
      imageDirectory: null,
      imageBuilder: widget.preview.imageBuilder,
      checkboxBuilder: null,
      bulletBuilder: null,
      builders: {
        BlankLineSyntax.tag: BlankLineBuilder(widget.preview.blankLineHeight),
      },
      paddingBuilders: const {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      fitContent: true,
      softLineBreak: true,
    ).build([widget.node]);
    return _rendered = children.length == 1
        ? children.single
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
  }
}
