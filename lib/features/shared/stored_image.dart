import 'dart:convert';

import 'package:flutter/material.dart';

/// Renders a stored image from either a signed HTTPS URL (Supabase) or a
/// `data:image/...;base64,...` URI (local mode).
class StoredImage extends StatelessWidget {
  const StoredImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:image')) {
      final separator = url.indexOf(',');
      if (separator > 0) {
        try {
          final bytes = base64Decode(url.substring(separator + 1));
          return Image.memory(
            bytes,
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
          );
        } catch (_) {
          // Fall through to the network renderer / error state.
        }
      }
    }
    return Image.network(url, fit: fit, width: width, height: height);
  }
}