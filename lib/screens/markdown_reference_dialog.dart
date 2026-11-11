import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../l10n/strings.dart';
import '../models/markdown_document.dart';
import '../services/markdown_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/document_toolbar_fields.dart';

class MarkdownReferenceDialog extends StatefulWidget {
  const MarkdownReferenceDialog({
    super.key,
    required this.initialDialect,
    required this.strings,
  });

  final MarkdownDialect initialDialect;
  final Strings strings;

  @override
  State<MarkdownReferenceDialog> createState() =>
      _MarkdownReferenceDialogState();
}

class _MarkdownReferenceDialogState extends State<MarkdownReferenceDialog> {
  late MarkdownDialect _dialect = widget.initialDialect;

  List<(String, String)> get _examples {
    final example = widget.strings['example'];
    return [
      ('referenceHeadings', '# Markdown\n## $example'),
      ('referenceEmphasis', '**Markdown** · *Markdown* · `Markdown`'),
      ('referenceLists', '- Markdown\n- $example\n\n1. Markdown\n2. $example'),
      ('referenceQuotes', '> $example'),
      ('referenceLinks', '[Markdown](https://commonmark.org/)'),
      ('referenceImages', '![Visor Markdown](logo.png)'),
      (
        'referenceCode',
        _dialect == MarkdownDialect.original
            ? '    print("Markdown")'
            : '```python\nprint("Markdown")\n```',
      ),
      ('referenceBreaks', 'Markdown  \n$example\n\n---\n\nMarkdown'),
      if (_dialect.supportsTables) ...[
        (
          'referenceTables',
          MarkdownService.exampleTable(
            2,
            columnLabel: example,
            cellLabel: example,
          ),
        ),
        ('referenceTasks', '- [x] Markdown\n- [ ] $example'),
        ('referenceStrike', '~~Markdown~~'),
        ('referenceAutolinks', 'https://commonmark.org/'),
        ('referenceFootnotes', 'Markdown[^1]\n\n[^1]: $example'),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final examples = _examples;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SizedBox(
        width: 800,
        height: math.min(700, MediaQuery.sizeOf(context).height - 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings['markdownReference'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: strings['close'],
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MarkdownStandardSelector(
                value: _dialect,
                strings: strings,
                onChanged: (value) => setState(() => _dialect = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  key: ValueKey(_dialect),
                  itemCount: examples.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final (label, source) = examples[index];
                    return _Example(
                      title: strings[label],
                      source: source,
                      dialect: _dialect,
                      strings: strings,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example({
    required this.title,
    required this.source,
    required this.dialect,
    required this.strings,
  });

  final String title;
  final String source;
  final MarkdownDialect dialect;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          source,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
      ),
    );
    final preview = Padding(
      padding: const EdgeInsets.all(8),
      child: MarkdownBody(
        data: source,
        extensionSet: dialect.extensions,
        imageBuilder: (_, _, _) => const AppLogo(size: 36),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                IconButton(
                  tooltip: strings['copy'],
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: source)),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 500) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [code, preview],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: code),
                    const SizedBox(width: 12),
                    Expanded(child: preview),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
