import 'dart:convert';

import '../models/diff_result.dart';

enum DiffKind { equal, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.endOfFile = false});
  final DiffKind kind;
  final String text;
  final bool endOfFile;
}

class DiffService {
  /// Align replacements, insertions and deletions into equal-height rows.
  /// Only actual source lines receive numbers; padding and EOF markers do not.
  static DiffResult sideBySide(String before, String after) {
    final lines = compare(before, after);
    final rows = <DiffRow>[];
    var leftNumber = 1;
    var rightNumber = 1;
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (line.kind == DiffKind.equal) {
        rows.add(
          DiffRow(
            left: line.text,
            right: line.text,
            leftLine: leftNumber++,
            rightLine: rightNumber++,
          ),
        );
        index++;
        continue;
      }
      final removed = <DiffLine>[];
      final added = <DiffLine>[];
      while (index < lines.length &&
          lines[index].kind != DiffKind.equal &&
          !lines[index].endOfFile) {
        final change = lines[index++];
        (change.kind == DiffKind.removed ? removed : added).add(change);
      }
      final count = removed.length > added.length
          ? removed.length
          : added.length;
      for (var row = 0; row < count; row++) {
        rows.add(
          DiffRow(
            left: row < removed.length ? removed[row].text : null,
            right: row < added.length ? added[row].text : null,
            leftLine: row < removed.length ? leftNumber++ : null,
            rightLine: row < added.length ? rightNumber++ : null,
            changed: true,
          ),
        );
      }
      if (index < lines.length && lines[index].endOfFile) {
        final eof = lines[index++];
        rows.add(
          DiffRow(
            left: eof.kind == DiffKind.removed ? eof.text : null,
            right: eof.kind == DiffKind.added ? eof.text : null,
            changed: true,
            endOfFile: true,
          ),
        );
      }
    }
    final hunks = <DiffHunk>[];
    for (var row = 0; row < rows.length;) {
      if (!rows[row].changed) {
        row++;
        continue;
      }
      final start = row;
      while (row < rows.length && rows[row].changed) {
        row++;
      }
      hunks.add(DiffHunk(start, row));
    }
    return DiffResult(rows, hunks);
  }

  /// LCS for normal documents; bounded fallback avoids quadratic allocation
  /// for large inputs. It remains lossless but may show a larger changed block.
  static List<DiffLine> compare(String before, String after) {
    final a = const LineSplitter().convert(before);
    final b = const LineSplitter().convert(after);
    if (before == after) {
      return a.map((s) => DiffLine(DiffKind.equal, s)).toList();
    }
    if (a.length * b.length > 1000000) {
      var prefix = 0;
      while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < a.length - prefix &&
          suffix < b.length - prefix &&
          a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
        suffix++;
      }
      return [
        ...a.take(prefix).map((s) => DiffLine(DiffKind.equal, s)),
        ...a
            .sublist(prefix, a.length - suffix)
            .map((s) => DiffLine(DiffKind.removed, s)),
        ...b
            .sublist(prefix, b.length - suffix)
            .map((s) => DiffLine(DiffKind.added, s)),
        ...a.skip(a.length - suffix).map((s) => DiffLine(DiffKind.equal, s)),
        if (before.endsWith('\n') != after.endsWith('\n'))
          DiffLine(
            before.endsWith('\n') ? DiffKind.removed : DiffKind.added,
            '↵',
            endOfFile: true,
          ),
      ];
    }
    final lengths = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        lengths[i][j] = a[i] == b[j]
            ? lengths[i + 1][j + 1] + 1
            : (lengths[i + 1][j] > lengths[i][j + 1]
                  ? lengths[i + 1][j]
                  : lengths[i][j + 1]);
      }
    }
    final result = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < a.length || j < b.length) {
      if (i < a.length && j < b.length && a[i] == b[j]) {
        result.add(DiffLine(DiffKind.equal, a[i++]));
        j++;
      } else if (i < a.length &&
          (j == b.length || lengths[i + 1][j] >= lengths[i][j + 1])) {
        result.add(DiffLine(DiffKind.removed, a[i++]));
      } else {
        result.add(DiffLine(DiffKind.added, b[j++]));
      }
    }
    // LineSplitter ignores the final newline; surface that difference too.
    if (before.endsWith('\n') != after.endsWith('\n')) {
      result.add(
        DiffLine(
          before.endsWith('\n') ? DiffKind.removed : DiffKind.added,
          '↵',
          endOfFile: true,
        ),
      );
    }
    return result;
  }
}
