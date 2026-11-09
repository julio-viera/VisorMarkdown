import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

import 'document_limits.dart';

class ImagePermissionRequired implements Exception {
  const ImagePermissionRequired(this.source);
  final String source;
}

/// Shared by preview and PDF. Permissions are exact-source and session-only.
class SafeImageLoader {
  SafeImageLoader({this.baseDirectory});
  final String? baseDirectory;
  static const maxBytes = 4 * 1024 * 1024;
  static const maxPixels = 4000000;
  static const totalPixels = 8000000;
  static const totalBytes = 16 * 1024 * 1024;
  final _allowed = <String>{};
  final _cache = <String, Future<Uint8List>>{};
  Future<void> _queue = Future.value();
  int _pixels = 0, _bytes = 0;
  bool _disposed = false;
  HttpClient? _client;

  void allow(String source) {
    _allowed.add(source);
    _cache.remove(source);
  }

  Future<Uint8List> load(String source) {
    if (_disposed) {
      return Future.error(const FormatException('Document closed'));
    }
    final existing = _cache[source];
    if (existing != null) return existing;
    if (_cache.length >= 12) {
      return Future.error(const FormatException('Image count limit: 12'));
    }
    final future = _queue.then((_) => _load(source));
    _cache[source] = future;
    _queue = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  Future<Uint8List> _load(String source) async {
    if (_disposed) throw const FormatException('Document closed');
    final uri = Uri.parse(source);
    Uint8List bytes;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (!_allowed.contains(source)) throw ImagePermissionRequired(source);
      _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 5);
      bytes =
          await (() async {
            final request = await _client!.getUrl(uri);
            // Redirect destinations require their own explicit permission.
            request.followRedirects = false;
            final response = await request.close();
            if (response.statusCode != 200 ||
                response.contentLength > maxBytes) {
              throw const FormatException('Image unavailable or too large');
            }
            final buffer = BytesBuilder(copy: false);
            await for (final chunk in response) {
              if (buffer.length + chunk.length > maxBytes) {
                throw const FormatException('Image too large');
              }
              buffer.add(chunk);
            }
            return buffer.takeBytes();
          })().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              _client?.close(force: true);
              _client = null;
              throw const FormatException('Image request timed out');
            },
          );
    } else if (uri.scheme == 'data') {
      if (source.length > maxBytes * 2) {
        throw const FormatException('Image too large');
      }
      bytes = uri.data!.contentAsBytes();
    } else if (uri.scheme.isEmpty || uri.scheme == 'file') {
      final location = uri.scheme == 'file'
          ? uri.toFilePath()
          : p.isAbsolute(Uri.decodeComponent(uri.path))
          ? Uri.decodeComponent(uri.path)
          : baseDirectory == null
          ? null
          : p.join(baseDirectory!, Uri.decodeComponent(uri.path));
      if (location == null) {
        throw const FormatException('Image has no document directory');
      }
      // Canonical paths prevent symlink escapes from the document directory.
      final canonical = await File(location).resolveSymbolicLinks();
      final base = baseDirectory == null
          ? null
          : await Directory(baseDirectory!).resolveSymbolicLinks();
      if ((base == null || !p.isWithin(base, canonical)) &&
          !_allowed.contains(source)) {
        throw ImagePermissionRequired(source);
      }
      bytes = await DocumentLimits.readBytes(File(canonical), maxBytes);
    } else {
      throw const FormatException('Unsupported image scheme');
    }
    if (_disposed) throw const FormatException('Document closed');
    final dimensions = validate(bytes);
    final pixels = dimensions.$1 * dimensions.$2;
    if (_pixels + pixels > totalPixels || _bytes + bytes.length > totalBytes) {
      throw const FormatException('Document image budget exceeded');
    }
    _pixels += pixels;
    _bytes += bytes.length;
    return bytes;
  }

  static (int, int) validate(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const FormatException('Image too large');
    final decoder = image.findDecoderForData(bytes);
    // A small raster allowlist avoids complex document/vector decoders.
    if (decoder is! image.PngDecoder &&
        decoder is! image.JpegDecoder &&
        decoder is! image.GifDecoder &&
        decoder is! image.WebPDecoder) {
      throw const FormatException('Unsupported image format');
    }
    final info = decoder!.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 8192 ||
        info.height > 8192 ||
        info.width * info.height > maxPixels ||
        info.numFrames > 1) {
      throw const FormatException('Image limit: 4 megapixels, one frame');
    }
    if ((info is image.PngInfo && info.isAnimated) ||
        (info is image.WebPInfo && info.hasAnimation) ||
        (decoder is image.GifDecoder &&
            decoder.info!.frames.any(
              (frame) =>
                  frame.width <= 0 ||
                  frame.height <= 0 ||
                  frame.x + frame.width > info.width ||
                  frame.y + frame.height > info.height,
            ))) {
      throw const FormatException('Animated or out-of-bounds image frame');
    }
    return (info.width, info.height);
  }

  void dispose() {
    _disposed = true;
    _client?.close(force: true);
    _cache.clear();
    _allowed.clear();
  }
}
