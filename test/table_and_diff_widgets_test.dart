import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:visor_markdown/main.dart';
import 'package:visor_markdown/controllers/workspace_controller.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/repositories/document_repository.dart';
import 'package:visor_markdown/services/markdown_service.dart';
import 'package:visor_markdown/screens/diff_dialog.dart';

class PdfRepository extends DocumentRepository {
  final completed = Completer<void>();
  Uint8List? exported;
  String? name;
  String? extension;
  @override
  Future<String?> saveBytesAs(
    String name,
    Uint8List bytes,
    String extension,
  ) async {
    this.name = name;
    this.extension = extension;
    exported = bytes;
    completed.complete();
    return '/export.pdf';
  }
}

void main() {
  Future<WorkspaceController> setup(
    WidgetTester tester, {
    DocumentRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = WorkspaceController(repository: repository, watch: false);
    await tester.pumpWidget(MarkdownApp(controller: c));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  test('all example tables parse with exactly 2 through 6 columns', () {
    for (var columns = 2; columns <= 6; columns++) {
      final source = MarkdownService.exampleTable(columns);
      final table =
          md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
                  .parse(source)
                  .single
              as md.Element;
      expect(table.tag, 'table');
      final head = table.children!.first as md.Element;
      final row = head.children!.single as md.Element;
      expect(row.children!.length, columns);
    }
    expect(() => MarkdownService.exampleTable(7), throwsRangeError);
  });
  testWidgets(
    'table insertion is gated by dialect and inserts at the editor cursor',
    (tester) async {
      final c = await setup(tester);
      final menu = find.byKey(const ValueKey('insert-table'));
      expect(c.active.dialect, MarkdownDialect.gfm);
      expect(tester.widget<PopupMenuButton<int>>(menu).enabled, true);
      await tester.tap(find.byKey(const ValueKey('markdown-standard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown Original').last);
      await tester.pumpAndSettle();
      expect(c.active.dialect, MarkdownDialect.original);
      expect(tester.widget<PopupMenuButton<int>>(menu).enabled, false);
      await tester.tap(find.byKey(const ValueKey('markdown-standard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark').last);
      await tester.pumpAndSettle();
      expect(c.active.dialect, MarkdownDialect.commonMark);
      expect(tester.widget<PopupMenuButton<int>>(menu).enabled, false);
      c.active.dialect = MarkdownDialect.gfm;
      c.active.editor.text = 'Before\n\nAfter';
      c.active.savedText = c.active.editor.text;
      c.active.editor.selection = const TextSelection.collapsed(offset: 8);
      c.changed();
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      for (var columns = 2; columns <= 6; columns++) {
        expect(find.text('$columns columns'), findsOneWidget);
      }
      await tester.tap(find.text('4 columns'));
      await tester.pumpAndSettle();
      expect(
        c.active.editor.text,
        startsWith('Before\n\n| Column 1 | Column 2 | Column 3 | Column 4 |'),
      );
      expect(c.active.editor.text, endsWith('\n\nAfter'));
      expect(c.active.dirty, true);
    },
  );
  testWidgets(
    'comparison has an independent action and aligned, navigable panels',
    (tester) async {
      final c = await setup(tester);
      final before = List.generate(100, (i) => 'Line ${i + 1}');
      final after = List.of(before)
        ..[5] = 'Changed near top'
        ..[80] = 'Changed near end';
      c.active.editor.text = before.join('\n');
      c.add(text: after.join('\n'));
      await tester.pumpAndSettle();
      final compare = find.byKey(const ValueKey('compare-action'));
      final settings = find.byKey(const ValueKey('settings-action'));
      expect(
        tester.getTopLeft(settings).dx - tester.getTopLeft(compare).dx,
        36,
      );
      await tester.tap(compare);
      await tester.pumpAndSettle();
      expect(find.byType(DiffDialog), findsOneWidget);
      expect(find.text('0/2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diff-next')));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diff-next')));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      ScrollableState scroll(String key) => tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Scrollable),
        ),
      );
      final left = scroll('diff-left-scroll');
      final right = scroll('diff-right-scroll');
      expect(left.position.pixels, greaterThan(0));
      expect(right.position.pixels, closeTo(left.position.pixels, .5));
      expect(find.text('81'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('diff-previous')));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(left.position.pixels, lessThan(300));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'identical documents disable difference navigation on a small screen',
    (tester) async {
      final c = await setup(tester);
      c.active.editor.text = 'identical';
      c.add(text: 'identical');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compare-action')));
      await tester.pumpAndSettle();
      expect(find.text('Documents are identical.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('diff-next')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('diff-previous')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('diff-left-scroll')), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-right-scroll')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'export menu creates actual PDF bytes without saving the source document',
    (tester) async {
      final repo = PdfRepository();
      final c = await setup(tester, repository: repo);
      c.active.editor.text = '# Export me';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-action')));
      await tester.pumpAndSettle();
      expect(find.text('Compare'), findsNothing);
      await tester.tap(find.text('Export · PDF'));
      await tester.runAsync(() async {
        await repo.completed.future.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(repo.extension, 'pdf');
      expect(repo.name, endsWith('.pdf'));
      expect(ascii.decode(repo.exported!.take(5).toList()), '%PDF-');
      expect(c.active.dirty, true);
    },
  );
}
