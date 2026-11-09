import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/models/markdown_document.dart';
import 'package:visor_markdown/services/markdown_service.dart';
import 'package:visor_markdown/services/diff_service.dart';

void main() {
  test('renderer changes extensions with the selected dialect', () {
    const source = '| A | B |\n| --- | --- |\n| one | two |\n\n~~removed~~';
    final original = MarkdownService.html(
      source,
      MarkdownDialect.original,
      'test',
    );
    final gfm = MarkdownService.html(source, MarkdownDialect.gfm, 'test');
    expect(original, isNot(contains('<table>')));
    expect(gfm, contains('<table>'));
    expect(gfm, contains('<del>removed</del>'));
    expect(
      MarkdownService.diagnostics(source, MarkdownDialect.original),
      contains('gfmWarning'),
    );
    expect(MarkdownService.diagnostics(source, MarkdownDialect.gfm), isEmpty);
  });
  test(
    'HTML exports escape title and embedded HTML and contain a restrictive CSP',
    () {
      final html = MarkdownService.html(
        '<script>alert(1)</script>',
        MarkdownDialect.commonMark,
        '<b>title</b>',
      );
      expect(html, contains('<title>&lt;b&gt;title&lt;/b&gt;</title>'));
      expect(html, isNot(contains('<script>')));
      expect(html, contains('Content-Security-Policy'));
    },
  );
  test(
    'plain text removes formatting and preserves text and image descriptions',
    () {
      expect(
        MarkdownService.plainText(
          '# Hello\n\n**World** ![image](x.png)',
          MarkdownDialect.commonMark,
        ),
        'Hello\n\nWorld image',
      );
    },
  );
  test('diff is lossless across additions, removals and a final newline', () {
    final diff = DiffService.compare('one\ntwo\n', 'one\nthree');
    expect(diff.where((l) => l.kind == DiffKind.removed).map((l) => l.text), [
      'two',
      '↵',
    ]);
    expect(diff.where((l) => l.kind == DiffKind.added).single.text, 'three');
    expect(diff.first.kind, DiffKind.equal);
  });
  test('large diff bounds allocation and retains common prefix and suffix', () {
    final before = ['start', ...List.filled(1100, 'old'), 'end'].join('\n');
    final after = ['start', ...List.filled(1100, 'new'), 'end'].join('\n');
    final diff = DiffService.compare(before, after);
    expect(diff.first.text, 'start');
    expect(diff.last.text, 'end');
    expect(diff.where((l) => l.kind == DiffKind.removed).length, 1100);
    expect(diff.where((l) => l.kind == DiffKind.added).length, 1100);
  });
}
