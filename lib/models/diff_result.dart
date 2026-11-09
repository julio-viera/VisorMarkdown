class DiffRow {
  const DiffRow({
    this.left,
    this.right,
    this.leftLine,
    this.rightLine,
    this.changed = false,
    this.endOfFile = false,
  });
  final String? left;
  final String? right;
  final int? leftLine;
  final int? rightLine;
  final bool changed;
  final bool endOfFile;
}

class DiffHunk {
  const DiffHunk(this.start, this.end);
  final int start;
  final int end;
}

class DiffResult {
  const DiffResult(this.rows, this.hunks);
  final List<DiffRow> rows;
  final List<DiffHunk> hunks;
  int get changedRows => rows.where((row) => row.changed).length;
}
