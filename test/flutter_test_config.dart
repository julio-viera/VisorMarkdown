import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:visor_markdown/app_info.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await AppInfo.load(bundle: _MetadataFileBundle());
  await testMain();
}

class _MetadataFileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
