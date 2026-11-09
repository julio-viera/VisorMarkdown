import 'package:flutter/material.dart';

import '../app_info.dart';
import '../l10n/strings.dart';
import '../widgets/app_logo.dart';

class AboutDialog extends StatelessWidget {
  const AboutDialog({
    super.key,
    required this.strings,
    required this.onOpenLink,
  });
  final Strings strings;
  final ValueChanged<String> onOpenLink;

  Widget field(
    BuildContext context,
    String label,
    String value, {
    String? url,
  }) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600);
    final valueWidget = url == null
        ? SelectableText(value)
        : Semantics(
            link: true,
            child: Tooltip(
              message: url,
              child: InkWell(
                onTap: () => onOpenLink(url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 420
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label:', style: labelStyle),
                  const SizedBox(height: 4),
                  valueWidget,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 136,
                    child: Text('$label:', style: labelStyle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: valueWidget),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 52),
          const SizedBox(height: 12),
          Text(
            s['aboutApp'].replaceAll('{app}', AppInfo.name),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              field(context, s['name'], AppInfo.name),
              field(context, s['version'], AppInfo.version),
              field(context, s['description'], AppInfo.description(s.language)),
              field(context, s['author'], AppInfo.author),
              field(
                context,
                s['license'],
                AppInfo.licenseName,
                url: AppInfo.licenseUrl,
              ),
              field(context, s['buildDate'], AppInfo.buildDate),
              field(
                context,
                s['repository'],
                AppInfo.repository,
                url: AppInfo.repository,
              ),
              field(context, s['issues'], AppInfo.issues, url: AppInfo.issues),
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
  }
}
