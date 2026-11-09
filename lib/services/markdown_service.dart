import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../models/markdown_document.dart';

class MarkdownService {
  static String exampleTable(
    int columns, {
    String columnLabel = 'Column',
    String cellLabel = 'Example',
  }) {
    if (columns < 2 || columns > 6) {
      throw RangeError.range(columns, 2, 6, 'columns');
    }
    String row(List<String> cells) => '| ${cells.join(' | ')} |';
    return [
      row(List.generate(columns, (i) => '$columnLabel ${i + 1}')),
      row(List.filled(columns, '---')),
      for (var r = 1; r <= 2; r++)
        row(List.generate(columns, (i) => '$cellLabel $r.${i + 1}')),
    ].join('\n');
  }

  /// Diagnostics describe portability, not invalid syntax: Markdown permits
  /// incomplete constructs and treats unsupported markup as ordinary text.
  static Set<String> diagnostics(String source, MarkdownDialect dialect) {
    final warnings = <String>{};
    if (RegExp(r'<\/?[A-Za-z][^>]*>').hasMatch(source)) {
      warnings.add('htmlWarning');
    }
    if (dialect != MarkdownDialect.gfm &&
        (RegExp(
              r'^\s*\|?.+\|.+\n\s*\|?\s*:?-{3,}',
              multiLine: true,
            ).hasMatch(source) ||
            RegExp(r'^\s*[-*+] \[[ xX]\]', multiLine: true).hasMatch(source) ||
            RegExp(r'~~.+?~~').hasMatch(source))) {
      warnings.add('gfmWarning');
    }
    if (dialect == MarkdownDialect.original &&
        RegExp(r'^\s{0,3}(`{3,}|~{3,})', multiLine: true).hasMatch(source)) {
      warnings.add('fenceWarning');
    }
    return warnings;
  }

  static String html(String source, MarkdownDialect dialect, String title) {
    final body = md.markdownToHtml(
      source,
      extensionSet: dialect.extensions,
      encodeHtml: true,
      enableTagfilter: true,
    );
    return '<!doctype html>\n<html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; style-src \'unsafe-inline\'">'
        '<title>${const HtmlEscape(HtmlEscapeMode.element).convert(title)}</title>'
        '<style>body{max-width:900px;margin:3em auto;padding:0 1em;font:17px/1.6 system-ui}'
        'pre,code{background:#f1f3f5}pre{padding:1em;overflow:auto}'
        'table{border-collapse:collapse}td,th{border:1px solid #999;padding:.5em}'
        'img{max-width:100%}blockquote{border-left:4px solid #aaa;padding-left:1em}</style>'
        '</head><body>$body</body></html>\n';
  }

  static String plainText(String source, MarkdownDialect dialect) {
    final nodes = md.Document(
      extensionSet: dialect.extensions,
      encodeHtml: false,
    ).parseLines(const LineSplitter().convert(source));
    return nodes.map(_text).join('\n\n');
  }

  static String _text(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      if (node.tag == 'br') return '\n';
      if (node.tag == 'img') return node.attributes['alt'] ?? '';
      final separator =
          {'ul', 'ol', 'table', 'thead', 'tbody', 'tr'}.contains(node.tag)
          ? '\n'
          : '';
      return (node.children ?? []).map(_text).join(separator);
    }
    return '';
  }
}
