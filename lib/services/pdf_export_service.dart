import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart';
import 'safe_image_loader.dart';
import 'document_limits.dart';
import '../models/markdown_document.dart';

/// Native, paginated export using the same Markdown dialect as the preview.
class PdfExportService {
  static Future<Uint8List> render(
    String source,
    MarkdownDialect dialect,
    String title, {
    String? baseDirectory,
    SafeImageLoader? imageLoader,
  }) async {
    DocumentLimits.validate(source);
    final fonts = <pw.Font>[];
    for (final name in [
      'LiberationSans-Regular',
      'LiberationSans-Bold',
      'LiberationSans-Italic',
      'LiberationSans-BoldItalic',
      'DejaVuSansMono',
    ]) {
      fonts.add(pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf')));
    }
    final theme = pw.ThemeData.withFont(
      base: fonts[0],
      bold: fonts[1],
      italic: fonts[2],
      boldItalic: fonts[3],
      fontFallback: [fonts[4]],
    );
    final mono = fonts[4];
    final nodes = md.Document(
      extensionSet: dialect.extensions,
      encodeHtml: false,
    ).parse(source);
    final renderer = _PdfMarkdown(mono);
    final loader = imageLoader ?? SafeImageLoader(baseDirectory: baseDirectory);
    try {
      await renderer.loadImages(nodes, loader);
    } finally {
      if (imageLoader == null) loader.dispose();
    }
    final document = pw.Document(
      title: title,
      author: AppInfo.author,
      creator: AppInfo.name,
      theme: theme,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        maxPages: 10000,
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  title,
                  maxLines: 1,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        build: (_) =>
            nodes.isEmpty ? [pw.SizedBox(height: 1)] : renderer.blocks(nodes),
      ),
    );
    return document.save();
  }
}

class _PdfMarkdown {
  _PdfMarkdown(this.mono);
  final pw.Font mono;
  final images = <String, pw.ImageProvider>{};
  static const body = pw.TextStyle(fontSize: 11, lineSpacing: 3);

  Future<void> loadImages(List<md.Node> nodes, SafeImageLoader loader) async {
    final sources = <String>{};
    void collect(md.Node node) {
      if (node is! md.Element) return;
      if (node.tag == 'img' && node.attributes['src'] != null) {
        sources.add(node.attributes['src']!);
      }
      for (final child in node.children ?? <md.Node>[]) {
        collect(child);
      }
    }

    for (final node in nodes) {
      collect(node);
    }
    for (final source in sources) {
      try {
        final bytes = await loader.load(source);
        final decoded = image.decodeImage(bytes, frame: 0);
        if (decoded != null) images[source] = pw.ImageImage(decoded);
      } catch (_) {
        // Unavailable/unsupported images retain their descriptive alternative.
      }
    }
  }

  List<pw.InlineSpan> inline(List<md.Node> nodes, pw.TextStyle style) {
    final spans = <pw.InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(pw.TextSpan(text: node.text, style: style));
        continue;
      }
      if (node is! md.Element) continue;
      var next = style;
      pw.AnnotationUrl? link;
      switch (node.tag) {
        case 'strong':
          next = style.copyWith(fontWeight: pw.FontWeight.bold);
        case 'em':
          next = style.copyWith(fontStyle: pw.FontStyle.italic);
        case 'del':
          next = style.copyWith(decoration: pw.TextDecoration.lineThrough);
        case 'code':
          next = style.copyWith(
            font: mono,
            fontSize: (style.fontSize ?? 11) * .9,
          );
        case 'p':
          spans.addAll(inline(node.children ?? [], style));
          spans.add(pw.TextSpan(text: '\n', style: style));
          continue;
        case 'br':
          spans.add(pw.TextSpan(text: '\n', style: style));
          continue;
        case 'img':
          spans.add(
            pw.TextSpan(
              text:
                  '[${node.attributes['alt'] ?? node.attributes['src'] ?? 'Image'}]',
              style: style,
            ),
          );
          continue;
        case 'input':
          spans.add(
            pw.TextSpan(
              text: node.attributes.containsKey('checked') ? '[x] ' : '[ ] ',
              style: style,
            ),
          );
          continue;
        case 'a':
          final uri = Uri.tryParse(node.attributes['href'] ?? '');
          if (uri != null && ['http', 'https', 'mailto'].contains(uri.scheme)) {
            link = pw.AnnotationUrl(uri.toString());
          }
          next = style.copyWith(
            color: PdfColors.teal800,
            decoration: pw.TextDecoration.underline,
          );
      }
      spans.add(
        pw.TextSpan(
          children: inline(node.children ?? [], next),
          annotation: link,
        ),
      );
    }
    return spans;
  }

  pw.RichText rich(
    List<md.Node> nodes, {
    pw.TextStyle style = body,
    String prefix = '',
  }) => pw.RichText(
    overflow: pw.TextOverflow.span,
    text: pw.TextSpan(
      children: [
        if (prefix.isNotEmpty) pw.TextSpan(text: prefix, style: style),
        ...inline(nodes, style),
      ],
    ),
  );

  List<pw.Widget> blocks(List<md.Node> nodes, {int depth = 0}) {
    final widgets = <pw.Widget>[];
    for (final node in nodes) {
      if (node is md.Text) {
        widgets.add(pw.Text(node.text, style: body));
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? <md.Node>[];
      if (RegExp(r'^h[1-6]$').hasMatch(node.tag)) {
        final level = int.parse(node.tag.substring(1));
        widgets.add(pw.SizedBox(height: 10));
        widgets.add(
          rich(
            children,
            style: body.copyWith(
              fontSize: 24 - (level - 1) * 2.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      } else if (node.tag == 'table') {
        final rows = <md.Element>[];
        void collect(md.Element element) {
          if (element.tag == 'tr') {
            rows.add(element);
            return;
          }
          for (final child in element.children ?? <md.Node>[]) {
            if (child is md.Element) collect(child);
          }
        }

        collect(node);
        widgets.add(
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            defaultColumnWidth: const pw.FlexColumnWidth(),
            children: [
              for (final row in rows)
                pw.TableRow(
                  repeat:
                      row.children?.any(
                        (c) => c is md.Element && c.tag == 'th',
                      ) ??
                      false,
                  decoration:
                      (row.children?.any(
                            (c) => c is md.Element && c.tag == 'th',
                          ) ??
                          false)
                      ? const pw.BoxDecoration(color: PdfColors.grey200)
                      : null,
                  children: [
                    for (final cell in row.children ?? <md.Node>[])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: cell is md.Element
                            ? rich(
                                cell.children ?? [],
                                style: body.copyWith(
                                  fontSize: 9,
                                  fontWeight: cell.tag == 'th'
                                      ? pw.FontWeight.bold
                                      : pw.FontWeight.normal,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                  ],
                ),
            ],
          ),
        );
      } else if (node.tag == 'pre') {
        for (final line in const LineSplitter().convert(node.textContent)) {
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              color: PdfColors.grey100,
              child: pw.Text(
                line.isEmpty ? ' ' : line,
                style: pw.TextStyle(font: mono, fontSize: 9),
              ),
            ),
          );
        }
      } else if (node.tag == 'ul' || node.tag == 'ol') {
        var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final item in children.whereType<md.Element>()) {
          final prefix =
              '${List.filled(depth * 2, ' ').join()}${node.tag == 'ol' ? '${number++}.' : '•'} ';
          final content = <md.Node>[];
          final nested = <md.Node>[];
          for (final child in item.children ?? <md.Node>[]) {
            if (child is md.Element && ['ul', 'ol'].contains(child.tag)) {
              nested.add(child);
            } else {
              content.add(child);
            }
          }
          widgets.add(rich(content, prefix: prefix));
          if (nested.isNotEmpty) {
            widgets.addAll(blocks(nested, depth: depth + 1));
          }
        }
      } else if (node.tag == 'blockquote') {
        widgets.add(
          rich(
            children,
            prefix: '│ ',
            style: body.copyWith(
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
        );
      } else if (node.tag == 'hr') {
        widgets.add(pw.Divider(color: PdfColors.grey400));
      } else if (node.tag == 'p') {
        final meaningful = children
            .where((n) => n is! md.Text || n.text.trim().isNotEmpty)
            .toList();
        final imageNode =
            meaningful.length == 1 &&
                meaningful.first is md.Element &&
                (meaningful.first as md.Element).tag == 'img'
            ? meaningful.first as md.Element
            : null;
        final image = imageNode == null
            ? null
            : images[imageNode.attributes['src']];
        if (image != null) {
          widgets.add(
            pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxHeight: 380),
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          );
        } else {
          widgets.add(rich(children));
        }
      } else {
        widgets.addAll(blocks(children, depth: depth));
      }
      widgets.add(pw.SizedBox(height: 6));
    }
    return widgets;
  }
}
