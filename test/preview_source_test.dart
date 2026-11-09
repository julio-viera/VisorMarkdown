import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:visor_markdown/widgets/blank_line_preview.dart';
import 'package:visor_markdown/widgets/preview_source.dart';

void main() {
  test('preview ranges preserve dialect parsing and original CRLF offsets', () {
    final source = [
      'Setext heading',
      '==============',
      '',
      'Paragraph with [a link][ref] and a footnote[^note].',
      '',
      '> Quote',
      'continues here.',
      '',
      '  - [x] List item',
      '',
      '| A | B |',
      '| - | - |',
      '| 1 | 2 |',
      '',
      '```dart',
      'void main() {}',
      '',
      '```',
      '',
      '[ref]: https://example.com',
      '',
      '[^note]: A note.',
      '',
    ].join('\r\n');
    for (final dialect in [
      md.ExtensionSet.none,
      md.ExtensionSet.commonMark,
      md.ExtensionSet.gitHubFlavored,
    ]) {
      final expected = md.Document(
        extensionSet: dialect,
        blockSyntaxes: previewBlockSyntaxes(
          gfm: dialect == md.ExtensionSet.gitHubFlavored,
        ),
        encodeHtml: false,
      ).parse(previewWithTrailingLine(source));
      final actual = parsePreview(source, dialect);
      String html(List<md.Node> nodes) => md.renderToHtml(nodes);
      expect(html(actual.map((block) => block.node).toList()), html(expected));
      expect(actual.first.source, (
        start: 0,
        end: source.indexOf('\r\n\r\n') + 2,
      ));
      final quote = actual.singleWhere(
        (block) =>
            block.node is md.Element &&
            (block.node as md.Element).tag == 'blockquote',
      );
      expect(quote.source.start, source.indexOf('> Quote'));
      expect(quote.source.end, source.indexOf('\r\n\r\n  -') + 2);
      expect(
        actual.every((block) => block.source.end <= source.length),
        isTrue,
      );
    }
  });
}
