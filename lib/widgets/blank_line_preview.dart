import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Preview-only extension. Keep empty lines as layout nodes instead of letting
/// Markdown discard them. Code blocks still consume their own blank lines.
class BlankLineSyntax extends md.EmptyBlockSyntax {
  const BlankLineSyntax();
  static const tag = 'editor-blank-lines';

  @override
  md.Node parse(md.BlockParser parser) {
    var count = 0;
    parser.encounteredBlankLine = true;
    while (!parser.isDone && pattern.hasMatch(parser.current.content)) {
      count++;
      parser.advance();
    }
    return md.Element.empty(tag)..attributes['count'] = '$count';
  }
}

class BlankLineBuilder extends MarkdownElementBuilder {
  BlankLineBuilder(this.lineHeight);
  final double lineHeight;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => BlankLineSpacer(
    height: (int.tryParse(element.attributes['count'] ?? '') ?? 1) * lineHeight,
  );
}

/// LineSplitter omits the final empty editor line. Add a delimiter only to the
/// preview copy so an Enter at the end of the document has visible height too.
String previewWithTrailingLine(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized.endsWith('\n') ? '$normalized\n' : normalized;
}

/// A separate widget also makes visual spacing measurable without duplicate
/// keys when a document contains several runs of empty lines.
class BlankLineSpacer extends StatelessWidget {
  const BlankLineSpacer({super.key, required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

/// Line identities are local to each parser, including nested list parsers.
class PreviewLineIndex {
  final _indices = Expando<Map<Object, int>>();

  int indexOf(md.BlockParser parser, Object line) {
    final indices = _indices[parser] ??= (Map<Object, int>.identity()
      ..addEntries(
        parser.lines.indexed.map((pair) => MapEntry(pair.$2, pair.$1)),
      ));
    return indices[line]!;
  }
}

List<md.BlockSyntax> previewBlockSyntaxes({
  required bool gfm,
  PreviewLineIndex? lineIndex,
}) {
  final index = lineIndex ?? PreviewLineIndex();
  return [
    const BlankLineSyntax(),
    ListGapSyntax(
      gfm
          ? const md.UnorderedListWithCheckboxSyntax()
          : const md.UnorderedListSyntax(),
      index,
    ),
    ListGapSyntax(
      gfm
          ? const md.OrderedListWithCheckboxSyntax()
          : const md.OrderedListSyntax(),
      index,
    ),
  ];
}

/// The stock list parser removes empty lines between items and at the end of
/// a list. Restore only those removed lines, while keeping its numbering,
/// nesting, task-list handling and reference parsing unchanged.
class ListGapSyntax extends md.BlockSyntax {
  const ListGapSyntax(this.delegate, this.lineIndex);
  final PreviewLineIndex lineIndex;
  final md.ListSyntax delegate;
  static final _marker = RegExp(
    r'^([ \t]*)(?:[-+*]|[0-9]{1,9}[.)])(?:[ \t]+|$)',
  );

  @override
  RegExp get pattern => delegate.pattern;
  @override
  bool canParse(md.BlockParser parser) => delegate.canParse(parser);
  @override
  bool canEndBlock(md.BlockParser parser) => delegate.canEndBlock(parser);

  @override
  md.Node? parse(md.BlockParser parser) {
    final start = lineIndex.indexOf(parser, parser.current);
    final node = delegate.parse(parser);
    if (node is! md.Element) return node;
    final end = parser.isDone
        ? parser.lines.length
        : lineIndex.indexOf(parser, parser.current);
    final first = _marker.firstMatch(parser.lines[start].content);
    if (first == null) return node;
    final indent = first[1];
    final starts = <int>[];
    for (var line = start; line < end; line++) {
      final marker = _marker.firstMatch(parser.lines[line].content);
      if (marker != null && marker[1] == indent) starts.add(line);
    }
    final items = (node.children ?? [])
        .whereType<md.Element>()
        .where((e) => e.tag == 'li')
        .toList();
    if (starts.length != items.length) return node;
    for (var item = 0; item < items.length; item++) {
      final boundary = item + 1 < starts.length ? starts[item + 1] : end;
      var count = 0;
      for (
        var line = boundary - 1;
        line > starts[item] && parser.lines[line].isBlankLine;
        line--
      ) {
        count++;
      }
      if (count > 0) {
        items[item].children?.add(
          md.Element.empty(BlankLineSyntax.tag)..attributes['count'] = '$count',
        );
      }
    }
    return node;
  }
}
