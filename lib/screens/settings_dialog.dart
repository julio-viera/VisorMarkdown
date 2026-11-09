import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/app_settings.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.settings});
  final AppSettings settings;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final s = Strings(
        settings.locale?.languageCode ??
            Localizations.localeOf(context).languageCode,
      );
      return AlertDialog(
        title: Text(s['settings']),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ThemeMode>(
                  isExpanded: true,
                  initialValue: settings.theme,
                  decoration: InputDecoration(labelText: s['theme']),
                  items: ThemeMode.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            s[v.name],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    settings.theme = v!;
                    settings.update();
                  },
                ),
                DropdownButtonFormField<ThemePalette>(
                  key: const ValueKey('theme-palette'),
                  isExpanded: true,
                  initialValue: settings.palette,
                  decoration: InputDecoration(labelText: s['palette']),
                  items: ThemePalette.values
                      .map(
                        (palette) => DropdownMenuItem(
                          value: palette,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: palette.seed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  s[palette.labelKey],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (palette) {
                    if (palette != null) {
                      settings.palette = palette;
                      settings.update();
                    }
                  },
                ),
                SwitchListTile(
                  key: const ValueKey('theme-high-contrast'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['highContrast']),
                  value: settings.highContrast,
                  onChanged: (value) {
                    settings.highContrast = value;
                    settings.update();
                  },
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: settings.locale?.languageCode ?? 'system',
                  decoration: InputDecoration(labelText: s['language']),
                  items: {'system': s['system'], ...Strings.languages}.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    settings.locale = v == 'system' ? null : Locale(v!);
                    settings.update();
                  },
                ),
                for (final section in {
                  'ui': settings.ui,
                  'editor': settings.editor,
                  'preview': settings.preview,
                }.entries) ...[
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s[section.key],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: section.value.family,
                    decoration: InputDecoration(labelText: s['font']),
                    items: ['sans-serif', 'serif', 'monospace']
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(f, style: TextStyle(fontFamily: f)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      section.value.family = v!;
                      settings.update();
                    },
                  ),
                  Row(
                    children: [
                      Text('${s['size']}: ${section.value.size.round()}'),
                      Expanded(
                        child: Slider(
                          min: 10,
                          max: 32,
                          divisions: 22,
                          value: section.value.size,
                          onChanged: (v) {
                            section.value.size = v;
                            settings.update();
                          },
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    children: [
                      FilterChip(
                        label: Text(s['bold']),
                        selected: section.value.bold,
                        onSelected: (v) {
                          section.value.bold = v;
                          settings.update();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(s['italic']),
                        selected: section.value.italic,
                        onSelected: (v) {
                          section.value.italic = v;
                          settings.update();
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s['close']),
          ),
        ],
      );
    },
  );
}
