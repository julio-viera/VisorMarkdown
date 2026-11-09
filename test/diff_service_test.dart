import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/services/diff_service.dart';

void main() {
  test(
    'side by side aligns replacement rows and keeps original line numbers',
    () {
      final result = DiffService.sideBySide(
        'same\nold A\nold B\ntail',
        'same\nnew\ntail\nextra',
      );
      expect(result.rows.length, 5);
      expect(result.rows[1].left, 'old A');
      expect(result.rows[1].right, 'new');
      expect(result.rows[1].leftLine, 2);
      expect(result.rows[1].rightLine, 2);
      expect(result.rows[2].left, 'old B');
      expect(result.rows[2].right, isNull);
      expect(result.rows[2].rightLine, isNull);
      expect(result.rows[3].leftLine, 4);
      expect(result.rows[3].rightLine, 3);
      expect(result.rows[4].leftLine, isNull);
      expect(result.rows[4].rightLine, 4);
      expect(result.hunks.map((h) => [h.start, h.end]), [
        [1, 3],
        [4, 5],
      ]);
      expect(result.changedRows, 3);
    },
  );
  test('EOF markers have no invented source line number', () {
    final result = DiffService.sideBySide('one\n', 'one');
    expect(result.rows.last.endOfFile, true);
    expect(result.rows.last.leftLine, isNull);
    expect(result.rows.last.rightLine, isNull);
    expect(result.hunks.length, 1);
    final literal = DiffService.sideBySide('↵', 'different');
    expect(literal.rows.first.endOfFile, false);
    expect(literal.rows.first.leftLine, 1);
  });
  test('identical and empty comparisons have no change blocks', () {
    expect(DiffService.sideBySide('', '').rows, isEmpty);
    final identical = DiffService.sideBySide('one\n\ntwo', 'one\n\ntwo');
    expect(identical.hunks, isEmpty);
    expect(identical.rows[1].leftLine, 2);
    final added = DiffService.sideBySide('', 'new');
    expect(added.rows.single.leftLine, isNull);
    expect(added.rows.single.rightLine, 1);
  });
}
