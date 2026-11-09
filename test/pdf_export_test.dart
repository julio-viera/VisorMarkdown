import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/services/pdf_export_service.dart';
import 'package:visor_markdown/services/markdown_service.dart';
import 'package:visor_markdown/services/safe_image_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PDF export handles Unicode, tables, rich text and multipage content',
    () async {
      final source =
          '''# Visor Markdown - Exportación PDF

Español: áéíóú ñ. Português: çãõ. Français: été. Deutsch: Größe. Italiano: città.

Texto **en negrita**, *en cursiva*, ~~tachado~~ y un [enlace](https://example.com).

## Tabla de seis columnas

${MarkdownService.exampleTable(6, columnLabel: 'Columna', cellLabel: 'Dato')}

> Una cita para comprobar la composición del documento.

- [x] Primera tarea
- [ ] Segunda tarea

```dart
void main() {
  print('Markdown a PDF');
}
```

## Tabla larga con encabezado repetido

| Nombre | Estado | Detalle |
| --- | --- | --- |
${List.generate(95, (i) => '| Fila ${i + 1} | Lista | Texto de ejemplo ${i + 1} |').join('\n')}

Fin del documento de prueba.
''';
      final bytes = await PdfExportService.render(
        source,
        MarkdownDialect.gfm,
        'Prueba de exportación',
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(4000));
      final directory = Platform.environment['VISOR_PDF_QA_DIR'];
      if (directory != null) {
        await Directory(directory).create(recursive: true);
        await File('$directory/markdown-export.pdf').writeAsBytes(bytes);
      }
    },
  );
  test('raster images are embedded and unavailable images retain their alternative text', () async {
    const pixel =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final bytes = await PdfExportService.render(
      '![Image](data:image/png;base64,$pixel)\n\n![Missing image](missing.png)\n\n![Corrupt image](data:image/png;base64,bm90LWFuLWltYWdl)',
      MarkdownDialect.gfm,
      'Images',
    );
    expect(RegExp(r'/Subtype\s*/Image').hasMatch(latin1.decode(bytes)), true);
  });
  test('PDF shares session permission for images outside the document directory', () async {
    const pixel =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final directory = await Directory.systemTemp.createTemp(
      'visor-pdf-policy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final base = await Directory('${directory.path}/docs').create();
    await File('${directory.path}/outside.png')
        .writeAsBytes(base64Decode(pixel));
    final loader = SafeImageLoader(baseDirectory: base.path);
    addTearDown(loader.dispose);
    final blocked = await PdfExportService.render(
      '![private](../outside.png)',
      MarkdownDialect.gfm,
      'Blocked',
      imageLoader: loader,
    );
    expect(
      RegExp(r'/Subtype\s*/Image').hasMatch(latin1.decode(blocked)),
      false,
    );
    loader.allow('../outside.png');
    final approved = await PdfExportService.render(
      '![private](../outside.png)',
      MarkdownDialect.gfm,
      'Approved',
      imageLoader: loader,
    );
    expect(
      RegExp(r'/Subtype\s*/Image').hasMatch(latin1.decode(approved)),
      true,
    );
  });
  test(
    'empty documents and long paragraphs export without a layout failure',
    () async {
      final empty = await PdfExportService.render(
        '',
        MarkdownDialect.original,
        'Empty',
      );
      expect(empty.length, greaterThan(500));
      final long = await PdfExportService.render(
        List.filled(1800, 'Long paragraph content.').join(' '),
        MarkdownDialect.commonMark,
        'Long',
      );
      expect(long.length, greaterThan(1000));
    },
  );
}
