import 'package:flutter/material.dart';

/// The document controller itself paints matches, preserving native editing,
/// IME composing ranges, selection, and accessibility.
class SearchEditorController extends TextEditingController {
  SearchEditorController({super.text});
  String query = '';
  String? _cachedText, _cachedQuery;
  List<TextRange> _matches = const [];
  List<TextRange> matchesFor(String search) {
    if (_cachedText != text || _cachedQuery != search) {
      _cachedText = text;
      _cachedQuery = search;
      _matches = search.isEmpty
          ? const []
          : List.unmodifiable(
              RegExp(RegExp.escape(search), caseSensitive: false)
                  .allMatches(text)
                  .map((m) => TextRange(start: m.start, end: m.end)),
            );
    }
    return _matches;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (query.isEmpty ||
        (withComposing &&
            value.composing.isValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in matchesFor(query)) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFD86B),
            color: Colors.black,
          ),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}
