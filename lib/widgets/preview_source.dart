import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import 'blank_line_preview.dart';

typedef SourceRange = ({int start, int end});
typedef PreviewBlock = ({md.Node node, SourceRange source});

/// Parse the full document so references and dialect rules remain global.
/// Record the character ranges consumed by its top-level block syntaxes.
List<PreviewBlock> parsePreview(String source, md.ExtensionSet extensions) {
  final starts = [
    0,
    ...RegExp(r'\r\n|\r|\n').allMatches(source).map((m) => m.end),
  ];
  final ranges = Expando<SourceRange>();
  final lineIndex = PreviewLineIndex();
  final tracker = _SourceTracker(starts, source.length, ranges, lineIndex);
  final custom = [
    ...previewBlockSyntaxes(
      gfm: extensions == md.ExtensionSet.gitHubFlavored,
      lineIndex: lineIndex,
    ),
    ...extensions.blockSyntaxes,
  ];
  final defaults = md.BlockParser(
    [],
    md.Document(extensionSet: md.ExtensionSet.none),
  ).blockSyntaxes;
  final document = md.Document(
    blockSyntaxes: [
      tracker,
      for (final syntax in [...custom, ...defaults])
        switch (syntax) {
          md.ParagraphSyntax() => _Paragraph(tracker),
          md.SetextHeaderSyntax() => _Setext(tracker),
          md.CodeBlockSyntax() => _Code(tracker),
          md.LinkReferenceDefinitionSyntax() ||
          md.EmptyBlockSyntax() when syntax is! BlankLineSyntax => syntax,
          _ => _TrackedSyntax(syntax, tracker),
        },
    ],
    extensionSet: md.ExtensionSet([], extensions.inlineSyntaxes),
    withDefaultBlockSyntaxes: false,
    encodeHtml: false,
  );

  return [
    for (final node in document.parseLines(
      const LineSplitter().convert(previewWithTrailingLine(source)),
    ))
      // The parser appends a synthetic section for collected footnotes.
      (
        node: node,
        source: ranges[node] ?? (start: source.length, end: source.length),
      ),
  ];
}

class _SourceTracker extends md.BlockSyntax {
  _SourceTracker(this.starts, this.length, this.ranges, this.lineIndex);
  final List<int> starts;
  final int length;
  final Expando<SourceRange> ranges;
  md.BlockParser? _root;
  final PreviewLineIndex lineIndex;

  @override
  RegExp get pattern => _never;
  static final _never = RegExp(r'(?!)');

  @override
  bool canParse(md.BlockParser parser) {
    _root ??= parser;
    return false;
  }

  @override
  md.Node? parse(md.BlockParser parser) => null;

  md.Node? track(
    md.BlockParser parser,
    md.Node? Function(md.BlockParser) parse,
  ) {
    if (!identical(parser, _root)) return parse(parser);
    final first = lineIndex.indexOf(parser, parser.linesToConsume.first);
    final node = parse(parser);
    if (node != null) {
      final next = parser.isDone
          ? starts.length
          : lineIndex.indexOf(parser, parser.current);
      ranges[node] = (
        start: starts[first],
        end: next < starts.length ? starts[next] : length,
      );
    }
    return node;
  }
}

class _TrackedSyntax extends md.BlockSyntax {
  const _TrackedSyntax(this.syntax, this.tracker);
  final md.BlockSyntax syntax;
  final _SourceTracker tracker;
  @override
  RegExp get pattern => syntax.pattern;
  @override
  bool canParse(md.BlockParser parser) => syntax.canParse(parser);
  @override
  bool canEndBlock(md.BlockParser parser) => syntax.canEndBlock(parser);
  @override
  md.Node? parse(md.BlockParser parser) => tracker.track(parser, syntax.parse);
}

// The Markdown parser checks these concrete types when resolving paragraphs,
// indented code and setext headings.
class _Paragraph extends md.ParagraphSyntax {
  const _Paragraph(this.tracker);
  final _SourceTracker tracker;
  @override
  md.Node? parse(md.BlockParser parser) => tracker.track(parser, super.parse);
}

class _Setext extends md.SetextHeaderSyntax {
  const _Setext(this.tracker);
  final _SourceTracker tracker;
  @override
  md.Node? parse(md.BlockParser parser) => tracker.track(parser, super.parse);
}

class _Code extends md.CodeBlockSyntax {
  const _Code(this.tracker);
  final _SourceTracker tracker;
  @override
  md.Node parse(md.BlockParser parser) => tracker.track(parser, super.parse)!;
}
