import 'document_limits.dart';

import 'package:flutter/services.dart';

import '../repositories/document_repository.dart';

/// Android ACTION_VIEW documents, both at startup and while already running.
class ExternalDocumentService {
  ExternalDocumentService({MethodChannel? channel})
    : channel =
          channel ??
          const MethodChannel('io.github.julio_viera.VisorMarkdown/file_open');
  final MethodChannel channel;
  bool _disposed = false;

  Future<void> start({
    required void Function(OpenedFile) onDocument,
    required void Function(Object) onError,
  }) async {
    void deliver(dynamic value) {
      if (_disposed) return;
      try {
        if (value is! Map) throw const FormatException('Invalid document');
        if (value['error'] != null) {
          throw FormatException(value['error'].toString());
        }
        final bytes = value['bytes'];
        if (bytes is! Uint8List) {
          throw const FormatException('Missing document content');
        }
        onDocument(
          OpenedFile(
            value['name'] as String? ?? 'document.md',
            DocumentLimits.decode(bytes),
            null,
            sourceId: value['sourceId'] as String?,
          ),
        );
      } catch (error) {
        onError(error);
      }
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'openDocument') deliver(call.arguments);
    });
    try {
      final documents = await channel.invokeListMethod<dynamic>(
        'getInitialDocuments',
      );
      for (final document in documents ?? []) {
        deliver(document);
      }
    } catch (error) {
      if (!_disposed) onError(error);
    }
  }

  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
