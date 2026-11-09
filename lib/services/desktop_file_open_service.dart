import 'package:flutter/services.dart';

/// Ordered, startup-safe delivery from the native single-instance launchers.
class DesktopFileOpenService {
  DesktopFileOpenService({MethodChannel? channel})
    : channel =
          channel ??
          const MethodChannel(
            'io.github.julio_viera.VisorMarkdown/desktop_file_open',
          );
  final MethodChannel channel;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  Future<void> start({
    required Future<void> Function(List<String>) onOpenPaths,
    required void Function(Object) onError,
  }) async {
    var initializing = true;
    final early = <dynamic>[];
    void enqueue(dynamic payload) {
      _queue = _queue.then((_) async {
        if (_disposed) return;
        try {
          if (payload is! Map ||
              payload['paths'] is! List ||
              (payload['paths'] as List).any(
                (p) => p is! String || p.isEmpty,
              )) {
            throw const FormatException('Invalid file-open request');
          }
          await onOpenPaths(List<String>.from(payload['paths']));
        } catch (error) {
          if (!_disposed) onError(error);
        }
      });
    }

    channel.setMethodCallHandler((call) async {
      if (call.method != 'openRequest' || _disposed) return;
      if (initializing) {
        early.add(call.arguments);
      } else {
        enqueue(call.arguments);
      }
    });
    try {
      final initial = await channel
          .invokeListMethod<dynamic>('getInitialRequests')
          .timeout(const Duration(seconds: 5));
      for (final request in initial ?? []) {
        enqueue(request);
      }
    } catch (error) {
      if (!_disposed) onError(error);
    }
    initializing = false;
    for (final request in early) {
      enqueue(request);
    }
    await _queue;
  }

  Future<void> flush() => _queue;
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
