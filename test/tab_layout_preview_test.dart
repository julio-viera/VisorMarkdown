import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/widgets/anchored_preview.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/models/app_settings.dart';
import 'package:visor_markdown/widgets/document_tab_strip.dart';

void main() {
  testWidgets(
    'recent small previews retain rendered state, with bounded eviction',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WorkspaceController(watch: false);
      c.active.editor.text = '# First\n\nA paragraph with **bold text**.';
      final first = c.active;
      await tester.pumpWidget(MarkdownApp(controller: c));
      await tester.pumpAndSettle();
      final firstState = tester.state(find.byType(AnchoredPreview));
      final firstRenderedText = tester.widget<SelectableText>(
        find
            .descendant(
              of: find.byType(AnchoredPreview),
              matching: find.byType(SelectableText),
            )
            .first,
      );
      c.add(text: '# Second\n\nAnother paragraph.');
      final second = c.active;
      await tester.pumpAndSettle();
      final secondState = tester.state(find.byType(AnchoredPreview));
      c.select(0);
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(AnchoredPreview)), firstState),
        true,
      );
      expect(
        identical(
          tester.widget<SelectableText>(
            find
                .descendant(
                  of: find.byType(AnchoredPreview),
                  matching: find.byType(SelectableText),
                )
                .first,
          ),
          firstRenderedText,
        ),
        true,
      );
      c.select(1);
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(AnchoredPreview)), secondState),
        true,
      );
      second.editor.text += '\n\nUpdated content';
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnchoredPreview>(find.byType(AnchoredPreview)).data,
        contains('Updated content'),
      );
      c.add(text: '# Third');
      await tester.pumpAndSettle();
      expect(firstState.mounted, false);
      expect(
        find.byType(AnchoredPreview, skipOffstage: false),
        findsNWidgets(2),
      );
      c.active.editor.text = List.filled(1100, 'x' * 45).join('\n');
      await tester.pumpAndSettle();
      expect(secondState.mounted, false);
      expect(find.byType(AnchoredPreview, skipOffstage: false), findsOneWidget);
      c.close(first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('44 KiB preview mounts nearby blocks and groups rapid edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(watch: false);
    final source = List.generate(
      375,
      (i) =>
          '# Section $i\n\nA paragraph with **bold text** and a '
          '[link](https://example.com) to a good page about Markdown documents.',
    ).join('\n\n');
    expect(source.length, closeTo(44 * 1024, 1024));
    final doc = c.active;
    doc.editor.text = source;
    await tester.pumpWidget(MarkdownApp(controller: c));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    await tester.pumpAndSettle();

    final preview = find.byType(AnchoredPreview);
    final blocks = find.descendant(
      of: preview,
      matching: find.byType(SelectableText),
    );
    expect(find.text('Section 0'), findsOneWidget);
    expect(blocks.evaluate().length, lessThan(50));
    final editor = find.byKey(ValueKey('editor-${doc.id}'));
    for (final suffix in ['A', 'AB', 'ABC']) {
      await tester.enterText(editor, '$source$suffix');
      await tester.pump(const Duration(milliseconds: 60));
      expect(doc.editor.text, '$source$suffix');
      expect(tester.widget<AnchoredPreview>(preview).data, source);
    }
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<AnchoredPreview>(preview).data, '${source}ABC');

    // Edits that continue arriving within the idle delay still refresh.
    for (var i = 0; i < 7; i++) {
      doc.editor.text = '$source update $i';
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<AnchoredPreview>(preview).data, '$source update 6');
    doc.scrollSync.revealEditor!(source.indexOf('# Section 370'));
    await tester.pumpAndSettle();
    expect(find.text('Section 370'), findsOneWidget);
    expect(blocks.evaluate().length, lessThan(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'toolbar owns right-hand actions and curved tabs stay separate from window controls',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final qa = Platform.environment['VISOR_LAYOUT_QA_DIR'];
      if (qa != null) {
        await tester.runAsync(() async {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          for (final entry in {
            'sans-serif': 'LiberationSans-Regular',
            'monospace': 'DejaVuSansMono',
          }.entries) {
            final loader = FontLoader(entry.key)
              ..addFont(rootBundle.load('assets/fonts/${entry.value}.ttf'));
            await loader.load();
          }
        });
      }
      final c = WorkspaceController(watch: false);
      c.active.path = qa == null
          ? '/tmp/guia.md'
          : '/tmp/Guía de uso e instalación de Visor Markdown.md';
      c.active.editor.text = '# Guía de ejemplo\n\nTexto con **negrita** y una lista:\n\n- Primera opción\n- Segunda opción\n';
      c.add(text: '# Notas\n\nOtro documento.', name: 'notas.md');
      c.select(0);
      final settings = AppSettings()
        ..customWindowChrome = true
        ..roundedWindowCorners = true
        ..theme = ThemeMode.light
        ..locale = const Locale('es');
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MarkdownApp(controller: c, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('document-toolbar'));
      final strip = find.byType(DocumentTabStrip);
      for (final key in [
        'new-tab-action',
        'export-action',
        'compare-action',
        'settings-action',
      ]) {
        expect(
          find.descendant(of: toolbar, matching: find.byKey(ValueKey(key))),
          findsOneWidget,
        );
        expect(
          find.descendant(of: strip, matching: find.byKey(ValueKey(key))),
          findsNothing,
        );
      }
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const ValueKey('window-close')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('new-tab-action'))).dx,
        greaterThan(1000),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('new-tab-action'))).dy,
        tester.getCenter(find.byTooltip('Abrir')).dy,
      );
      final firstTab = tester.getRect(
        find.byKey(ValueKey('tab-${c.documents[0].id}')),
      );
      final secondTab = tester.getRect(
        find.byKey(ValueKey('tab-${c.documents[1].id}')),
      );
      expect(firstTab.right, greaterThan(secondTab.left));
      final path = const CurvedTabShape().getOuterPath(
        const Rect.fromLTWH(0, 0, 200, 38),
      );
      expect(path.contains(const Offset(100, 20)), true);
      expect(path.contains(const Offset(10, 20)), true);
      expect(path.contains(const Offset(190, 20)), false);
      expect(path.contains(const Offset(1, 20)), false);
      expect(path.contains(const Offset(1, 37.99)), true);
      if (qa != null) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          settings.theme = mode;
          settings.update();
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(qa).create(recursive: true);
            await File('$qa/tabs-${mode.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      for (final width in [480.0, 320.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: toolbar,
            matching: find.byKey(const ValueKey('settings-action')),
          ),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
