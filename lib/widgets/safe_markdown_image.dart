import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/safe_image_loader.dart';

class SafeMarkdownImage extends StatefulWidget {
  const SafeMarkdownImage({
    super.key,
    required this.loader,
    required this.source,
    required this.alt,
    required this.strings,
  });
  final SafeImageLoader loader;
  final String source, alt;
  final Strings strings;
  @override
  State<SafeMarkdownImage> createState() => _SafeMarkdownImageState();
}

class _SafeMarkdownImageState extends State<SafeMarkdownImage> {
  late Future<Uint8List> pending = widget.loader.load(widget.source);
  MemoryImage? provider;
  @override
  void didUpdateWidget(SafeMarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        oldWidget.source != widget.source) {
      provider?.evict();
      provider = null;
      pending = widget.loader.load(widget.source);
    }
  }

  @override
  void dispose() {
    provider?.evict();
    super.dispose();
  }

  Future<void> authorize() async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings['loadImage']),
        content: SingleChildScrollView(
          child: Text(
            '${widget.strings['imagePermission']}\n\n${widget.source.length > 1000 ? '${widget.source.substring(0, 1000)}…' : widget.source}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings['cancel']),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings['loadImage']),
          ),
        ],
      ),
    );
    if (allow != true || !mounted) return;
    widget.loader.allow(widget.source);
    setState(() => pending = widget.loader.load(widget.source));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: pending,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        provider ??= MemoryImage(snapshot.data!);
        return Image(
          image: provider!,
          errorBuilder: (_, _, _) => Text(widget.alt),
        );
      }
      if (snapshot.error is ImagePermissionRequired) {
        return TextButton.icon(
          onPressed: authorize,
          icon: const Icon(Icons.shield_outlined),
          label: Text('${widget.strings['loadImage']}: ${widget.alt}'),
        );
      }
      return Text('${widget.strings['imageUnavailable']}: ${widget.alt}');
    },
  );
}
