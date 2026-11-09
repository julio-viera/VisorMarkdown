import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor_markdown/app_info.dart';

void main() {
  final json = File('assets/app_info.json').readAsStringSync();

  test('loads the release version without a tag prefix', () {
    expect(AppInfo.version, jsonDecode(json)['version']);
    expect(AppInfo.version, matches(RegExp(r'^[0-9]')));
  });

  test('rejects a version with a tag prefix', () async {
    final metadata = jsonDecode(json) as Map<String, dynamic>;
    metadata['version'] = 'v${metadata['version']}';
    await expectLater(
      AppInfo.load(bundle: _Bundle(metadata)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects missing required fields and translations', () async {
    for (final field in ['author', 'buildNumber', 'descriptions.es']) {
      final metadata = jsonDecode(json) as Map<String, dynamic>;
      if (field == 'descriptions.es') {
        (metadata['descriptions'] as Map<String, dynamic>).remove('es');
      } else {
        metadata.remove(field);
      }
      await expectLater(
        AppInfo.load(bundle: _Bundle(metadata)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'field',
            contains(field),
          ),
        ),
      );
    }
  });
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.metadata);
  final Map<String, dynamic> metadata;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
  );
}
