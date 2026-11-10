import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:image/image.dart' as image;

import '../models/markdown_document.dart';
import 'document_limits.dart';
import 'safe_image_loader.dart';

enum OfficeFormat { docx, odt }

class OfficeExportService {
  static Future<Uint8List> render(
    String source,
    MarkdownDialect dialect,
    OfficeFormat format, {
    SafeImageLoader? imageLoader,
  }) async {
    final nodes = await compute(_parse, (source, dialect));
    final images = <String, Uint8List>{};
    if (imageLoader != null) {
      final sources = <String>{};
      void collect(md.Node node) {
        if (node is! md.Element) return;
        final source = node.attributes['src'];
        if (node.tag == 'img' && source != null) sources.add(source);
        _children(node).forEach(collect);
      }

      nodes.forEach(collect);
      for (final source in sources) {
        try {
          images[source] = await imageLoader.load(source);
        } catch (_) {
          // Missing, denied and unsupported images keep their alternative text.
        }
      }
    }
    return compute(_render, (nodes, format, images));
  }

  static List<md.Node> _parse((String, MarkdownDialect) request) {
    final (source, dialect) = request;
    DocumentLimits.validate(source);
    return md.Document(
      extensionSet: dialect.extensions,
      encodeHtml: false,
    ).parse(source);
  }

  static Uint8List _render(
    (List<md.Node>, OfficeFormat, Map<String, Uint8List>) request,
  ) {
    final (nodes, format, images) = request;
    return _OfficeDocument(format, images).encode(nodes);
  }
}

const _xml = '<?xml version="1.0" encoding="UTF-8"?>';
const _wordNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _relationshipNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _odtMime = 'application/vnd.oasis.opendocument.text';
final _xmlCharacters = RegExp(
  r'[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]',
  unicode: true,
);
String _escape(String value) =>
    const HtmlEscape().convert(value.replaceAll(_xmlCharacters, '\uFFFD'));
List<md.Node> _children(md.Element node) => node.children ?? const [];

enum _Emphasis { bold, italic, strike, code, link }

class _OfficeDocument {
  _OfficeDocument(this.format, this.imageBytes);
  final OfficeFormat format;
  final Map<String, Uint8List> imageBytes;
  final pictures =
      <String, ({int id, Uint8List png, double width, double height})?>{};
  int drawingCount = 0;
  bool get word => format == OfficeFormat.docx;
  final links = <String, String>{};
  final lists = <({bool ordered, int start, int depth})>[];
  final spanStyles = <String, Set<_Emphasis>>{};
  int tableCount = 0;

  Uint8List encode(List<md.Node> nodes) {
    final body = _blocks(nodes);
    final archive = Archive();
    if (word) {
      for (final entry in _wordParts(body).entries) {
        archive.addFile(ArchiveFile.string(entry.key, entry.value));
      }
    } else {
      final mime = ascii.encode(_odtMime);
      archive.addFile(ArchiveFile.noCompress('mimetype', mime.length, mime));
      archive.addFile(ArchiveFile.string('content.xml', _odtContent(body)));
      archive.addFile(
        ArchiveFile.string(
          'META-INF/manifest.xml',
          '$_xml<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">'
              '<manifest:file-entry manifest:full-path="/" manifest:media-type="$_odtMime" manifest:version="1.3"/>'
              '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>'
              '${pictures.values.nonNulls.map((picture) => '<manifest:file-entry manifest:full-path="Pictures/image${picture.id}.png" manifest:media-type="image/png"/>').join()}'
              '</manifest:manifest>',
        ),
      );
    }
    final directory = word ? 'word/media' : 'Pictures';
    for (final picture in pictures.values.nonNulls) {
      archive.addFile(
        ArchiveFile.bytes('$directory/image${picture.id}.png', picture.png),
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static const _blockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'table',
    'hr',
  };

  String _blocks(List<md.Node> nodes, {int depth = 0, bool quote = false}) {
    final output = StringBuffer();
    final pending = <md.Node>[];
    void flush() {
      if (pending.isEmpty) return;
      output.write(_paragraph(_inline(pending), style: quote ? 'Quote' : null));
      pending.clear();
    }

    for (final node in nodes) {
      if (node is! md.Element || !_blockTags.contains(node.tag)) {
        pending.add(node);
        continue;
      }
      flush();
      final children = _children(node);
      output.write(switch (node.tag) {
        'ul' || 'ol' => _list(node, depth),
        'table' => _table(node),
        'blockquote' => _blocks(children, depth: depth, quote: true),
        'pre' => _paragraph(
          _run(node.textContent.replaceFirst(RegExp(r'\n$'), ''), {
            _Emphasis.code,
          }),
          style: 'Code',
        ),
        'hr' => _paragraph('', style: 'Rule'),
        'p' => _paragraph(_inline(children), style: quote ? 'Quote' : null),
        _ => _paragraph(_inline(children), heading: int.parse(node.tag[1])),
      });
    }
    flush();
    return output.toString();
  }

  String _inline(List<md.Node> nodes, [Set<_Emphasis> style = const {}]) =>
      nodes.map((node) {
        if (node is md.Text) return _run(node.text, style);
        if (node is! md.Element) return '';
        final children = _children(node);
        return switch (node.tag) {
          'strong' => _inline(children, {...style, _Emphasis.bold}),
          'em' => _inline(children, {...style, _Emphasis.italic}),
          'del' || 's' => _inline(children, {...style, _Emphasis.strike}),
          'code' => _run(node.textContent, {...style, _Emphasis.code}),
          'br' => _run('\n', style),
          'img' => _picture(node, style),
          'input' => _run(
            node.attributes.containsKey('checked') ? '☑ ' : '☐ ',
            style,
          ),
          'a' => _link(node, style),
          _ => _inline(children, style),
        };
      }).join();

  String _picture(md.Element node, Set<_Emphasis> style) {
    final source = node.attributes['src'];
    final alt = node.attributes['alt'] ?? '';
    final bytes = imageBytes[source];
    if (source == null || bytes == null) return _run(alt, style);
    final picture = pictures.putIfAbsent(source, () {
      try {
        final decoded = image.decodeImage(bytes, frame: 0);
        if (decoded == null) return null;
        final scale = math.min(
          1.0,
          math.min(576 / decoded.width, 672 / decoded.height),
        );
        return (
          id: pictures.length + 1,
          png: image.encodePng(decoded, level: 1),
          width: decoded.width * scale,
          height: decoded.height * scale,
        );
      } catch (_) {
        return null;
      }
    });
    if (picture == null) return _run(alt, style);
    final id = ++drawingCount;
    final description = _escape(alt);
    if (!word) {
      final width = (picture.width / 96).toStringAsFixed(4);
      final height = (picture.height / 96).toStringAsFixed(4);
      return '<draw:frame draw:name="Image $id" text:anchor-type="as-char" svg:width="${width}in" svg:height="${height}in">'
          '<draw:image xlink:href="Pictures/image${picture.id}.png" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/>'
          '<svg:desc>$description</svg:desc></draw:frame>';
    }

    final width = (picture.width * 9525).round();
    final height = (picture.height * 9525).round();
    const pictureNs =
        'http://schemas.openxmlformats.org/drawingml/2006/picture';
    return '<w:r><w:drawing><wp:inline>'
        '<wp:extent cx="$width" cy="$height"/><wp:docPr id="$id" name="Image $id" descr="$description"/>'
        '<a:graphic><a:graphicData uri="$pictureNs"><pic:pic xmlns:pic="$pictureNs">'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="Image $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="image${picture.id}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$width" cy="$height"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  String _link(md.Element node, Set<_Emphasis> style) {
    final children = _children(node);
    final uri = Uri.tryParse(node.attributes['href'] ?? '');
    if (uri == null || !{'http', 'https', 'mailto'}.contains(uri.scheme)) {
      return _inline(children, style);
    }
    final content = _inline(children, {...style, _Emphasis.link});
    if (!word) {
      return '<text:a xlink:type="simple" xlink:href="${_escape(uri.toString())}">$content</text:a>';
    }
    final id = links.putIfAbsent(
      uri.toString(),
      () => 'link${links.length + 1}',
    );
    return '<w:hyperlink r:id="$id">$content</w:hyperlink>';
  }

  static final _wordSpacing = RegExp(r'[\r\n\t]+|[^\r\n\t]+');
  static final _spacing = RegExp(r'[\r\n\t]+| +|[^\r\n\t ]+');
  String _run(String value, Set<_Emphasis> style) {
    if (value.isEmpty) return '';
    final spacing = word ? _wordSpacing : _spacing;
    final content = spacing.allMatches(value.replaceAll('\r\n', '\n')).map((
      match,
    ) {
      final text = match[0]!;
      return switch (text[0]) {
        '\r' || '\n' || '\t' =>
          text
              .split('')
              .map(
                (char) => word
                    ? (char == '\t' ? '<w:tab/>' : '<w:br/>')
                    : (char == '\t' ? '<text:tab/>' : '<text:line-break/>'),
              )
              .join(),
        ' ' when !word => '<text:s text:c="${text.length}"/>',
        _ =>
          word
              ? '<w:t xml:space="preserve">${_escape(text)}</w:t>'
              : _escape(text),
      };
    }).join();
    if (word) {
      final properties = [
        if (style.contains(_Emphasis.code))
          '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/>',
        if (style.contains(_Emphasis.bold)) '<w:b/>',
        if (style.contains(_Emphasis.italic)) '<w:i/>',
        if (style.contains(_Emphasis.strike)) '<w:strike/>',
        if (style.contains(_Emphasis.link))
          '<w:color w:val="1557A0"/><w:u w:val="single"/>',
      ].join();
      return '<w:r>${properties.isEmpty ? '' : '<w:rPr>$properties</w:rPr>'}$content</w:r>';
    }
    if (style.isEmpty) return content;
    final id =
        'Inline${_Emphasis.values.where(style.contains).map((item) => item.index).join()}';
    spanStyles[id] = style;
    return '<text:span text:style-name="$id">$content</text:span>';
  }

  String _paragraph(String content, {String? style, int? heading, int? list}) {
    final name = heading == null ? style : 'Heading$heading';
    if (word) {
      final properties = [
        if (name != null) '<w:pStyle w:val="$name"/>',
        if (list != null)
          '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="$list"/></w:numPr>',
      ].join();
      return '<w:p>${properties.isEmpty ? '' : '<w:pPr>$properties</w:pPr>'}$content</w:p>';
    }
    final tag = heading == null ? 'p' : 'h';
    return '<text:$tag${name == null ? '' : ' text:style-name="$name"'}'
        '${heading == null ? '' : ' text:outline-level="$heading"'}>$content</text:$tag>';
  }

  String _list(md.Element node, int depth) {
    final ordered = node.tag == 'ol';
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final items = _children(node).whereType<md.Element>();
    if (!word) {
      return '<text:list text:style-name="${ordered ? 'Numbered' : 'Bullets'}">'
          '${items.indexed.map((entry) {
            final (index, item) = entry;
            final startValue = ordered && index == 0 && start != 1 ? ' text:start-value="$start"' : '';
            final content = _blocks(_children(item), depth: depth + 1);
            return '<text:list-item$startValue>${content.isEmpty ? _paragraph('') : content}</text:list-item>';
          }).join()}</text:list>';
    }

    lists.add((ordered: ordered, start: start, depth: depth));
    final listId = lists.length;
    return items.map((item) {
      final children = _children(item);
      final firstBlock = children.indexWhere(
        (child) => child is md.Element && _blockTags.contains(child.tag),
      );
      final String first;
      final int next;
      if (firstBlock == 0 && (children.first as md.Element).tag == 'p') {
        first = _inline(_children(children.first as md.Element));
        next = 1;
      } else {
        next = firstBlock < 0 ? children.length : firstBlock;
        first = _inline(children.take(next).toList());
      }
      return _paragraph(first, list: listId) +
          _blocks(children.skip(next).toList(), depth: depth + 1);
    }).join();
  }

  String _table(md.Element node) {
    final rows = _children(node)
        .whereType<md.Element>()
        .expand(
          (section) =>
              _children(section)
                  .whereType<md.Element>()
                  .map((row) => (row: row, header: section.tag == 'thead')),
        )
        .toList();
    if (rows.isEmpty) return '';
    final columns = _children(rows.first.row).length;
    final output = StringBuffer(
      word
          ? '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders>'
                '${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((side) => '<w:$side w:val="single" w:sz="4" w:color="B7BEC7"/>').join()}'
                '</w:tblBorders></w:tblPr><w:tblGrid>${'<w:gridCol/>' * columns}</w:tblGrid>'
          : '<table:table table:name="Table${++tableCount}"><table:table-column table:number-columns-repeated="$columns"/>',
    );
    for (final entry in rows) {
      if (!word && entry.header) output.write('<table:table-header-rows>');
      output.write(
        word
            ? '<w:tr>${entry.header ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}'
            : '<table:table-row>',
      );
      for (final cell in _children(entry.row).whereType<md.Element>()) {
        final content = _paragraph(
          _inline(_children(cell), {if (entry.header) _Emphasis.bold}),
        );
        output.write(
          word
              ? '<w:tc>$content</w:tc>'
              : '<table:table-cell table:style-name="Cell" office:value-type="string">$content</table:table-cell>',
        );
      }
      output.write(word ? '</w:tr>' : '</table:table-row>');
      if (!word && entry.header) output.write('</table:table-header-rows>');
    }
    output.write(word ? '</w:tbl>' : '</table:table>');
    return output.toString();
  }

  String _relationships(String entries) =>
      '$_xml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$entries</Relationships>';

  Map<String, String> _wordParts(String body) {
    const type =
        'application/vnd.openxmlformats-officedocument.wordprocessingml';
    return {
      '[Content_Types].xml':
          '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '${drawingCount == 0 ? '' : '<Default Extension="png" ContentType="image/png"/>'}'
          '<Override PartName="/word/document.xml" ContentType="$type.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="$type.styles+xml"/>'
          '${lists.isEmpty ? '' : '<Override PartName="/word/numbering.xml" ContentType="$type.numbering+xml"/>'}'
          '</Types>',
      '_rels/.rels': _relationships(
        '<Relationship Id="document" Type="$_relationshipNs/officeDocument" Target="word/document.xml"/>',
      ),
      'word/document.xml':
          '$_xml<w:document xmlns:w="$_wordNs" xmlns:r="$_relationshipNs"'
          ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"'
          ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body>$body</w:body></w:document>',
      'word/_rels/document.xml.rels': _relationships(
        [
          '<Relationship Id="styles" Type="$_relationshipNs/styles" Target="styles.xml"/>',
          if (lists.isNotEmpty)
            '<Relationship Id="numbering" Type="$_relationshipNs/numbering" Target="numbering.xml"/>',
          for (final picture in pictures.values.nonNulls)
            '<Relationship Id="image${picture.id}" Type="$_relationshipNs/image" Target="media/image${picture.id}.png"/>',
          for (final entry in links.entries)
            '<Relationship Id="${entry.value}" Type="$_relationshipNs/hyperlink" Target="${_escape(entry.key)}" TargetMode="External"/>',
        ].join(),
      ),
      'word/styles.xml':
          '$_xml<w:styles xmlns:w="$_wordNs">'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
          '<w:pPr><w:spacing w:after="120"/></w:pPr></w:style>'
          '${List.generate(6, (i) => _wordStyle('Heading${i + 1}', 'heading ${i + 1}', '<w:keepNext/><w:spacing w:before="240" w:after="100"/><w:outlineLvl w:val="$i"/>', '<w:b/><w:sz w:val="${_headingSize(i) * 2}"/>')).join()}'
          '${_wordStyle('Code', 'Code', '<w:shd w:fill="F2F4F6"/><w:spacing w:before="120" w:after="120"/>', '')}'
          '${_wordStyle('Quote', 'Quote', '<w:ind w:left="360"/>', '<w:i/>')}'
          '${_wordStyle('Rule', 'Rule', '<w:pBdr><w:bottom w:val="single" w:sz="4" w:color="B7BEC7"/></w:pBdr>', '')}'
          '</w:styles>',
      if (lists.isNotEmpty) 'word/numbering.xml': _wordNumbering(),
    };
  }

  static int _headingSize(int index) => [24, 20, 17, 15, 13, 12][index];
  static String _wordStyle(String id, String name, String para, String run) =>
      '<w:style w:type="paragraph" w:styleId="$id"><w:name w:val="$name"/><w:basedOn w:val="Normal"/>'
      '<w:pPr>$para</w:pPr><w:rPr>$run</w:rPr></w:style>';

  String _wordNumbering() {
    final abstracts = lists.indexed.map((entry) {
      final (index, list) = entry;
      return '<w:abstractNum w:abstractNumId="$index"><w:multiLevelType w:val="singleLevel"/>'
          '<w:lvl w:ilvl="0"><w:start w:val="${list.start}"/><w:numFmt w:val="${list.ordered ? 'decimal' : 'bullet'}"/>'
          '<w:lvlText w:val="${list.ordered ? '%1.' : '•'}"/><w:lvlJc w:val="left"/>'
          '<w:pPr><w:ind w:left="${720 + 360 * list.depth}" w:hanging="360"/></w:pPr>'
          '</w:lvl></w:abstractNum>';
    }).join();
    final instances = lists.indexed
        .map(
          (entry) =>
              '<w:num w:numId="${entry.$1 + 1}"><w:abstractNumId w:val="${entry.$1}"/></w:num>',
        )
        .join();
    return '$_xml<w:numbering xmlns:w="$_wordNs">$abstracts$instances</w:numbering>';
  }

  String _odtContent(String body) =>
      '$_xml<office:document-content office:version="1.3"'
      ' xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"'
      ' xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"'
      ' xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"'
      ' xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"'
      ' xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"'
      ' xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"'
      ' xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"'
      ' xmlns:xlink="http://www.w3.org/1999/xlink">'
      '<office:automatic-styles>'
      '${List.generate(6, (i) => '<style:style style:name="Heading${i + 1}" style:family="paragraph">'
          '<style:paragraph-properties fo:keep-with-next="always" fo:margin-top="0.35cm" fo:margin-bottom="0.15cm"/>'
          '<style:text-properties fo:font-size="${_headingSize(i)}pt" fo:font-weight="bold"/></style:style>').join()}'
      '<style:style style:name="Code" style:family="paragraph"><style:paragraph-properties fo:background-color="#f2f4f6" fo:margin-top="0.2cm" fo:margin-bottom="0.2cm"/></style:style>'
      '<style:style style:name="Quote" style:family="paragraph"><style:paragraph-properties fo:margin-left="0.6cm" fo:margin-top="0.15cm" fo:margin-bottom="0.15cm"/>'
      '<style:text-properties fo:font-style="italic"/></style:style>'
      '<style:style style:name="Rule" style:family="paragraph"><style:paragraph-properties fo:border-bottom="0.5pt solid #b7bec7"/></style:style>'
      '<style:style style:name="Cell" style:family="table-cell"><style:table-cell-properties fo:border="0.5pt solid #b7bec7" fo:padding="0.10cm"/></style:style>'
      '${spanStyles.entries.map((entry) => '<style:style style:name="${entry.key}" style:family="text">'
          '<style:text-properties ${_odtTextProperties(entry.value)}/></style:style>').join()}'
      '${_odtListStyle(false)}${_odtListStyle(true)}'
      '</office:automatic-styles><office:body><office:text>$body</office:text></office:body></office:document-content>';

  String _odtTextProperties(Set<_Emphasis> style) => [
    if (style.contains(_Emphasis.bold)) 'fo:font-weight="bold"',
    if (style.contains(_Emphasis.italic)) 'fo:font-style="italic"',
    if (style.contains(_Emphasis.strike))
      'style:text-line-through-style="solid"',
    if (style.contains(_Emphasis.code)) 'fo:font-family="Courier New"',
    if (style.contains(_Emphasis.link))
      'fo:color="#1557a0" style:text-underline-style="solid"',
  ].join(' ');

  String _odtListStyle(bool ordered) {
    final tag = ordered ? 'number' : 'bullet';
    return '<text:list-style style:name="${ordered ? 'Numbered' : 'Bullets'}">'
        '${List.generate(10, (i) => '<text:list-level-style-$tag text:level="${i + 1}" '
            '${ordered ? 'style:num-format="1" style:num-suffix="."' : 'text:bullet-char="•"'}>'
            '<style:list-level-properties text:space-before="${(i + 1) * 0.5}cm" text:min-label-width="0.5cm"/>'
            '</text:list-level-style-$tag>').join()}</text:list-style>';
  }
}
