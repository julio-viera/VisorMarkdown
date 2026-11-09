import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/l10n/strings.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/widgets/document_tab_strip.dart';

void main() {
  testWidgets(
    'titles expand, compress to the old minimum and then scroll without selection jitter',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final docs = [
        MarkdownDocument(id: 1, name: 'a.md'),
        MarkdownDocument(
          id: 2,
          name: 'Documento detallado con notas y especificaciones de implementación.md',
        ),
      ];
      var width = 1400.0;
      var active = 0;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: DocumentTabStrip(
                      documents: List.of(docs),
                      activeIndex: active,
                      strings: Strings('en'),
                      onSelect: (index) => setState(() => active = index),
                      onClose: (_) {},
                      actions: const [],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      Finder tab(int id) => find.byKey(ValueKey('tab-$id'));
      double tabWidth(int id) => tester.getSize(tab(id)).width;
      ScrollPosition position() =>
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      final minimum = tabWidth(1);
      final natural = tabWidth(2);
      expect(minimum, 200); // Old 190px scroll slot + overlap - outer padding.
      expect(natural, greaterThan(minimum));
      expect(position().maxScrollExtent, 0);
      await tester.tap(tab(2));
      await tester.pumpAndSettle();
      expect(tabWidth(2), natural);
      update(() => width = 600);
      await tester.pumpAndSettle();
      expect(tabWidth(1), minimum);
      expect(tabWidth(2), inExclusiveRange(minimum, natural));
      expect(position().maxScrollExtent, closeTo(0, .01));
      update(() => width = 360);
      await tester.pumpAndSettle();
      expect(tabWidth(1), minimum);
      expect(tabWidth(2), minimum);
      expect(position().maxScrollExtent, greaterThan(0));
      expect(position().pixels, greaterThan(0));
      final close = find.descendant(
        of: tab(2),
        matching: find.byType(IconButton),
      );
      expect(close.hitTestable(), findsOneWidget);
      final offset = position().pixels;
      update(
        () => docs[1].path = '/tmp/Un documento renombrado con un título aún más largo que debe aprovechar de nuevo el espacio disponible.md',
      );
      await tester.pumpAndSettle();
      expect(position().pixels, offset);
      update(() => width = 1400);
      await tester.pumpAndSettle();
      expect(tabWidth(2), greaterThan(minimum));
      expect(position().maxScrollExtent, closeTo(0, .01));
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      for (final doc in docs) {
        doc.dispose();
      }
    },
  );
}
