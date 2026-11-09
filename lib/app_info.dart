import 'dart:convert';

import 'package:flutter/services.dart';

import 'l10n/strings.dart';

/// The bundled JSON is the source of application and release metadata.
class AppInfo {
  static late Map<String, String> _fields;
  static late Map<String, String> _descriptions;

  static Future<void> load({AssetBundle? bundle}) async {
    final data = jsonDecode(
      await (bundle ?? rootBundle).loadString('assets/app_info.json'),
    );
    if (data is! Map<String, dynamic>) {
      throw const FormatException('app_info.json must contain a JSON object');
    }

    String requiredText(Object? value, String field) {
      if (value is! String ||
          value.trim().isEmpty ||
          value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw FormatException('Invalid or missing app_info.json field: $field');
      }
      return value;
    }

    final fields = {
      for (final key in [
        'name',
        'version',
        'buildDate',
        'author',
        'licenseName',
        'licenseSpdx',
        'licenseUrl',
        'repository',
        'issues',
        'applicationId',
        'binary',
      ])
        key: requiredText(data[key], key),
    };
    if (!RegExp(
      r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$',
    ).hasMatch(fields['version']!)) {
      throw const FormatException('Invalid app_info.json field: version');
    }
    final buildNumber = data['buildNumber'];
    if (buildNumber is! int || buildNumber < 1) {
      throw const FormatException(
        'Invalid or missing app_info.json field: buildNumber',
      );
    }
    final descriptions = data['descriptions'];
    if (descriptions is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid or missing app_info.json field: descriptions',
      );
    }
    final localized = {
      for (final locale in Strings.locales)
        locale.languageCode: requiredText(
          descriptions[locale.languageCode],
          'descriptions.${locale.languageCode}',
        ),
    };
    _fields = fields;
    _descriptions = localized;
  }

  static String get name => _fields['name']!;
  static String get version => _fields['version']!;
  static String get author => _fields['author']!;
  static String get licenseName => _fields['licenseName']!;
  static String get licenseSpdx => _fields['licenseSpdx']!;
  static String get licenseUrl => _fields['licenseUrl']!;
  static String get repository => _fields['repository']!;
  static String get issues => _fields['issues']!;
  static String get buildDate => _fields['buildDate']!;

  static String description(String language) =>
      _descriptions[language] ??
      (throw FormatException('Missing app_info.json description: $language'));
}
