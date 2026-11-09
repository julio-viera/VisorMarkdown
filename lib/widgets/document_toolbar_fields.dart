import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/markdown_document.dart';

class MarkdownStandardSelector extends StatelessWidget {
  const MarkdownStandardSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.strings,
  });
  final MarkdownDialect value;
  final ValueChanged<MarkdownDialect> onChanged;
  final Strings strings;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: colors.outlineVariant.withValues(alpha: .7),
      ),
    );
    return Tooltip(
      message: strings['markdownStandard'],
      child: DropdownButtonFormField<MarkdownDialect>(
        key: const ValueKey('markdown-standard'),
        initialValue: value,
        isExpanded: true,
        isDense: true,
        style: Theme.of(context).textTheme.bodyMedium,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: colors.surfaceContainerLow,
        elevation: 4,
        icon: const Icon(Icons.unfold_more_rounded, size: 18),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          prefixIcon: Icon(
            Icons.code_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 40,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
        ),
        selectedItemBuilder: (_) => MarkdownDialect.values
            .map(
              (dialect) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  dialect == MarkdownDialect.gfm
                      ? 'GitHub · GFM'
                      : dialect.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        items: MarkdownDialect.values
            .map(
              (dialect) => DropdownMenuItem(
                value: dialect,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dialect.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (dialect == value)
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (dialect) {
          if (dialect != null) onChanged(dialect);
        },
      ),
    );
  }
}

class DocumentSearchField extends StatefulWidget {
  const DocumentSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.strings,
    required this.matchCount,
    required this.matchIndex,
    required this.onChanged,
    required this.onNavigate,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final Strings strings;
  final int matchCount, matchIndex;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onNavigate;
  @override
  State<DocumentSearchField> createState() => _DocumentSearchFieldState();
}

class _DocumentSearchFieldState extends State<DocumentSearchField> {
  bool focused = false;
  void navigate(int direction) {
    widget.onNavigate(direction);
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = widget.matchCount == 0 || widget.matchIndex < 0
        ? 0
        : widget.matchIndex % widget.matchCount + 1;
    Widget button(
      String label,
      IconData icon,
      VoidCallback? action, {
      Key? key,
    }) => IconButton(
      key: key,
      tooltip: label,
      onPressed: action,
      icon: Icon(icon, size: 17),
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 32),
        maximumSize: const Size(28, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    return Focus(
      onFocusChange: (value) {
        if (focused != value) setState(() => focused = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 40),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: .7),
            width: focused ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.search_rounded,
                size: 18,
                color: focused ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () =>
                      navigate(1),
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                      navigate(1),
                },
                child: TextField(
                  key: const ValueKey('search'),
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: widget.strings['search'],
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: widget.onChanged,
                  textInputAction: TextInputAction.search,
                  onEditingComplete: () {},
                  onSubmitted: (_) => navigate(1),
                ),
              ),
            ),
            if (widget.controller.text.isNotEmpty)
              button(widget.strings['clearSearch'], Icons.close_rounded, () {
                widget.controller.clear();
                widget.onChanged('');
                widget.focusNode.requestFocus();
              }, key: const ValueKey('clear-search')),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '$current/${widget.matchCount}',
                key: const ValueKey('search-count'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      widget.controller.text.isNotEmpty &&
                          widget.matchCount == 0
                      ? colors.error
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(
              height: 18,
              child: VerticalDivider(width: 1, color: colors.outlineVariant),
            ),
            button(
              widget.strings['previous'],
              Icons.keyboard_arrow_up_rounded,
              widget.matchCount == 0 ? null : () => navigate(-1),
            ),
            button(
              widget.strings['next'],
              Icons.keyboard_arrow_down_rounded,
              widget.matchCount == 0 ? null : () => navigate(1),
            ),
          ],
        ),
      ),
    );
  }
}
