import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/services/office_export_service.dart';
import 'package:visor_markdown/services/safe_image_loader.dart';

const _markdown = '''
# Ejemplo café 📝

Un párrafo con **negrita**, *cursiva*, ~~tachado~~ y [un enlace](https://example.org/?a=1&b=2).
Otro con [un enlace local](file:///private/example.md) y ![Descripción](imagen.png).

> Una cita

3. Primero
   - Anidado
4. Segundo

- [x] Revisado

| Nombre | Valor |
| ------ | ----- |
| A & B  | 42    |

```dart
if (x < 2) {
  print(x);
}
```
''';

void main() {
  test('Word export packages editable Markdown structures', () async {
    final bytes = await OfficeExportService.render(
      _markdown,
      MarkdownDialect.gfm,
      OfficeFormat.docx,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    String part(String name) => utf8.decode(archive.findFile(name)!.content);
    final body = part('word/document.xml');

    expect(part('_rels/.rels'), contains('Target="word/document.xml"'));
    expect(body, contains('<w:pStyle w:val="Heading1"/>'));
    expect(body, contains('Ejemplo café 📝'));
    expect(body, contains('<w:b/>'));
    expect(body, contains('<w:i/>'));
    expect(body, contains('<w:strike/>'));
    expect(body, contains('<w:tbl>'));
    expect(body, contains('<w:numPr>'));
    expect(part('word/numbering.xml'), contains('<w:start w:val="3"/>'));
    expect(body, contains('<w:br/>'));
    expect(body, contains('  print(x);'));
    expect(body, contains('A &amp; B'));
    expect(body, contains('Descripción'));
    final links = part('word/_rels/document.xml.rels');
    expect(links, contains('example.org'));
    expect(links, contains('a=1&amp;b=2'));
    expect(links, isNot(contains('file:')));
  });

  test('LibreOffice export uses a native OpenDocument package', () async {
    final bytes = await OfficeExportService.render(
      _markdown,
      MarkdownDialect.gfm,
      OfficeFormat.odt,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final mime = archive.files.first;
    expect(mime.name, 'mimetype');
    expect(mime.compression, CompressionType.none);
    expect(
      utf8.decode(mime.content),
      'application/vnd.oasis.opendocument.text',
    );
    final body = utf8.decode(archive.findFile('content.xml')!.content);
    expect(archive.findFile('META-INF/manifest.xml'), isNotNull);
    expect(body, contains('text:outline-level="1"'));
    expect(body, contains('Ejemplo'));
    expect(body, contains('café'));
    expect(body, contains('📝'));
    expect(body, contains('fo:font-weight="bold"'));
    expect(body, contains('style:text-line-through-style="solid"'));
    expect(body, contains('<table:table '));
    expect(body, contains('text:start-value="3"'));
    expect(body, contains('<text:line-break/>'));
    expect(body, contains('<text:s text:c="2"/>print(x);'));
    expect(body, contains('example.org'));
    expect(body, isNot(contains('file:')));
  });
  for (final format in OfficeFormat.values) {
    test(
      '${format.name} embeds allowed images and keeps alternative text for denied images',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'visor-office-images-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final documentFolder = await Directory('${directory.path}/document')
            .create();
        final png = image.encodePng(image.Image(width: 96, height: 48));
        await File('${documentFolder.path}/local.png').writeAsBytes(png);
        final outside = await File('${directory.path}/outside.png')
            .writeAsBytes(png);
        final loader = SafeImageLoader(baseDirectory: documentFolder.path);
        addTearDown(loader.dispose);
        final markdown =
            '![Local](local.png) ![Repeated](local.png) ![Outside](${outside.uri})';
        Future<Archive> export() async => ZipDecoder().decodeBytes(
          await OfficeExportService.render(
            markdown,
            MarkdownDialect.gfm,
            format,
            imageLoader: loader,
          ),
        );

        final word = format == OfficeFormat.docx;
        final media = word ? 'word/media/' : 'Pictures/';
        final bodyPath = word ? 'word/document.xml' : 'content.xml';
        final metadata = word
            ? 'word/_rels/document.xml.rels'
            : 'META-INF/manifest.xml';
        final denied = await export();
        expect(
          denied.files.where((file) => file.name.startsWith(media)),
          hasLength(1),
        );
        final body = utf8.decode(denied.findFile(bodyPath)!.content);
        final reference = word
            ? 'r:embed="image1"'
            : 'xlink:href="Pictures/image1.png"';
        expect(RegExp(reference).allMatches(body), hasLength(2));
        expect(
          body,
          contains(word ? 'descr="Local"' : '<svg:desc>Local</svg:desc>'),
        );
        expect(body, contains(word ? '>Outside</w:t>' : 'Outside</text:p>'));
        expect(
          utf8.decode(denied.findFile(metadata)!.content),
          contains('image1.png'),
        );
        final embedded = image.decodePng(
          denied.findFile('${media}image1.png')!.content,
        )!;
        expect((embedded.width, embedded.height), (96, 48));

        loader.allow(outside.uri.toString());
        final allowed = await export();
        expect(allowed.findFile('${media}image2.png'), isNotNull);
      },
    );
  }
}
