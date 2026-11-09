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
  late Future<Uint8List> pending;
  late bool allowed;
  MemoryImage? provider;
  @override
  void initState() {
    super.initState();
    _load();
    widget.loader.addListener(_permissionChanged);
  }

  void _load() {
    provider?.evict();
    provider = null;
    allowed = widget.loader.isAllowed(widget.source);
    pending = widget.loader.load(widget.source);
  }

  void _permissionChanged() {
    if (!allowed && widget.loader.isAllowed(widget.source)) {
      setState(_load);
    }
  }

  @override
  void didUpdateWidget(SafeMarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      oldWidget.loader.removeListener(_permissionChanged);
      widget.loader.addListener(_permissionChanged);
    }
    if (oldWidget.loader != widget.loader ||
        oldWidget.source != widget.source) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.loader.removeListener(_permissionChanged);
    provider?.evict();
    super.dispose();
  }

  Future<void> authorize() async {
    final loader = widget.loader;
    final source = widget.source;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings['loadImage']),
        content: SingleChildScrollView(
          child: Text(
            '${widget.strings['imagePermission']}\n\n${source.length > 1000 ? '${source.substring(0, 1000)}…' : source}',
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
    if (allow != true ||
        !mounted ||
        widget.loader != loader ||
        widget.source != source) {
      return;
    }
    loader.allow(source);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: pending,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Text(widget.alt);
      }
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
