import 'package:flutter/material.dart';

import '../l10n/strings.dart';

import '../services/unicode_catalog.dart';

class CharacterMapDialog extends StatefulWidget {
  const CharacterMapDialog({super.key, required this.strings});

  final Strings strings;

  @override
  State<CharacterMapDialog> createState() => _CharacterMapDialogState();
}

class _CharacterMapDialogState extends State<CharacterMapDialog> {
  late final _catalogFuture = UnicodeCatalog.load();
  final _scroll = ScrollController();
  bool? _icons;
  String? _category;
  var _query = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _resetScroll() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 600,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FutureBuilder<UnicodeCatalog>(
            future: _catalogFuture,
            builder: (context, snapshot) {
              final catalog = snapshot.data;
              final results = catalog?.find(
                _query,
                icons: _icons,
                category: _category,
              );
              return CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                strings['characterMap'],
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: strings['close'],
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        TextField(
                          autofocus: true,
                          onChanged: (value) {
                            _resetScroll();
                            setState(() => _query = value);
                          },
                          decoration: InputDecoration(
                            label: Text(
                              strings['characterSearch'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final (icons, label) in [
                              (null, 'characterAll'),
                              (false, 'characterSymbols'),
                              (true, 'characterIcons'),
                            ])
                              ChoiceChip(
                                label: Text(strings[label]),
                                selected: _icons == icons,
                                onSelected: (_) {
                                  _resetScroll();
                                  setState(() {
                                    _icons = icons;
                                    _category = null;
                                  });
                                },
                              ),
                          ],
                        ),
                        if (_icons case final icons?)
                          if (catalog != null)
                            DropdownButton<String>(
                              isExpanded: true,
                              value: _category ?? '',
                              onChanged: (value) {
                                _resetScroll();
                                setState(
                                  () => _category = value == '' ? null : value,
                                );
                              },
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text(
                                    strings['characterAllCategories'],
                                  ),
                                ),
                                for (final name in catalog.categories(
                                  icons: icons,
                                ))
                                  DropdownMenuItem(
                                    value: name,
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  if (results == null || results.length == 0)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: results == null && !snapshot.hasError
                            ? const CircularProgressIndicator()
                            : Text(
                                strings[snapshot.hasError
                                    ? 'error'
                                    : 'characterEmpty'],
                              ),
                      ),
                    )
                  else
                    SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 60,
                            mainAxisExtent: 50,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final entry = results[index];
                        return IconButton.filledTonal(
                          tooltip: '${entry.name} · ${entry.code}',
                          onPressed: () =>
                              Navigator.of(context).pop(entry.glyph),
                          icon: Text(
                            entry.glyph.trim().isEmpty
                                ? entry.code
                                : entry.glyph,
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
