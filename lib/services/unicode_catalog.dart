import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

String _hex(int point) => point.toRadixString(16).toUpperCase().padLeft(4, '0');

class UnicodeEntry {
  const UnicodeEntry(this.points, this.name);

  final List<int> points;
  final String name;

  String get glyph => String.fromCharCodes(points);
  String get code => points.map((point) => 'U+${_hex(point)}').join(' ');
}

class _Range {
  const _Range(this.points, this.last, this.name);

  final List<int> points;
  final int last;
  final String name;

  int get count => last - points.first + 1;

  UnicodeEntry entryAt(int offset) {
    if (offset == 0 && !name.contains('*')) return UnicodeEntry(points, name);
    final point = points.first + offset;
    return UnicodeEntry([point], name.replaceFirst('*', _hex(point)));
  }
}

class UnicodeResults {
  UnicodeResults(this._ranges) {
    var total = 0;
    for (final range in _ranges) {
      total += range.count;
      _ends.add(total);
    }
  }

  final List<_Range> _ranges;
  final _ends = <int>[];

  int get length => _ends.isEmpty ? 0 : _ends.last;

  UnicodeEntry operator [](int index) {
    var low = 0;
    var high = _ends.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_ends[middle] <= index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return _ranges[low].entryAt(index - (low == 0 ? 0 : _ends[low - 1]));
  }
}

class UnicodeCatalog {
  UnicodeCatalog._(this._blocks, this._icons) {
    _allCharacters = _select(_blocks, null);
    _allIcons = _select(_icons, null);
    _all = [
      ..._allCharacters,
      for (final group in _icons.entries)
        if (!_blocks.containsKey(group.key)) ...group.value,
    ];
    _everything = UnicodeResults([
      ..._allCharacters,
      ..._allIcons.where((range) => range.points.length > 1),
    ]);
  }

  late final List<_Range> _allCharacters;
  late final List<_Range> _allIcons;
  late final List<_Range> _all;
  late final UnicodeResults _everything;

  static UnicodeCatalog? _cached;
  static Future<UnicodeCatalog> load() async {
    if (_cached case final catalog?) return catalog;
    final data = await rootBundle.load('assets/unicode/catalog-17.tsv.gz');
    final catalog = await compute(
      _parse,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _cached = catalog;
    return catalog;
  }

  final Map<String, List<_Range>> _blocks;
  final Map<String, List<_Range>> _icons;

  Iterable<String> categories({required bool icons}) =>
      (icons ? _icons : _blocks).keys;

  UnicodeResults find(String query, {bool? icons, String? category}) {
    final ranges = switch (icons) {
      true => category == null ? _allIcons : _icons[category]!,
      false => category == null ? _allCharacters : _blocks[category]!,
      null => _all,
    };
    final text = query.trim().toLowerCase();
    if (text.isEmpty) {
      return icons == null ? _everything : UnicodeResults(ranges);
    }

    // A single non-ASCII symbol or a composed emoji can be pasted as-is.
    final codePattern = RegExp(
      r'^(?:(?:u\+|0x)?[0-9a-f]{4,6})(?:\s+(?:u\+|0x)?[0-9a-f]{4,6})*$',
    );
    final namedCode = RegExp(r'-([0-9a-f]{4,6})$').firstMatch(text);
    final codeQuery = namedCode?.group(1) ?? text;
    final List<int>? points = codePattern.hasMatch(codeQuery)
        ? codeQuery
              .split(RegExp(r'\s+'))
              .map(
                (part) => int.parse(
                  part.replaceFirst(RegExp(r'^(u\+|0x)'), ''),
                  radix: 16,
                ),
              )
              .toList()
        : text.runes.any((point) => point > 127) || text.length == 1
        ? query.trim().runes.toList()
        : null;

    final exact = <_Range>[];
    final matches = <_Range>[];
    final seen = <String>{};
    for (final range in ranges) {
      if (points != null &&
          points.length == 1 &&
          range.points.length == 1 &&
          points.first >= range.points.first &&
          points.first <= range.last) {
        final entry = range.entryAt(points.first - range.points.first);
        if ((namedCode == null || entry.name.toLowerCase() == text) &&
            seen.add(entry.points.join(' '))) {
          exact.add(_Range(entry.points, points.first, entry.name));
        }
      } else if (namedCode == null &&
          points != null &&
          listEquals(points, range.points)) {
        exact.add(range);
      } else if (range.name.toLowerCase().contains(text)) {
        if (range.count > 1 || seen.add(range.points.join(' '))) {
          matches.add(range);
        }
      }
    }
    return UnicodeResults(exact.isEmpty ? matches : exact);
  }

  static List<_Range> _select(
    Map<String, List<_Range>> groups,
    String? category,
  ) => category == null
      ? groups.values.expand((ranges) => ranges).toList()
      : groups[category]!;

  static UnicodeCatalog _parse(Uint8List bytes) {
    final blocks = <String, List<_Range>>{};
    final icons = <String, List<_Range>>{};
    var ranges = <_Range>[];
    for (final line in const LineSplitter().convert(
      utf8.decode(GZipDecoder().decodeBytes(bytes)),
    )) {
      final [code, name] = line.split('\t');
      if (code == 'b' || code == 'e') {
        ranges = [];
        (code == 'b' ? blocks : icons)[name] = ranges;
      } else {
        final bounds = code.split('..');
        final points = bounds.first
            .split(' ')
            .map((part) => int.parse(part, radix: 16))
            .toList();
        ranges.add(
          _Range(
            points,
            bounds.length == 1
                ? points.first
                : int.parse(bounds.last, radix: 16),
            name,
          ),
        );
      }
    }
    icons.removeWhere((_, entries) => entries.isEmpty);
    for (final name in [
      'Miscellaneous Symbols',
      'Dingbats',
      'Geometric Shapes',
    ]) {
      icons[name] = blocks[name]!;
    }
    return UnicodeCatalog._(blocks, icons);
  }
}
