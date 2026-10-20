import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compresses a receipt photo so the base64 string fits comfortably inside a
/// single Firestore document (1 MiB limit), keeping the receipt JSON atomic.
String? encodeReceiptImageForFirestore(
  Uint8List bytes, {
  int maxBase64Characters = 700000,
}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    for (final maxWidth in <int>[1600, 1200, 900, 700]) {
      final resized = decoded.width > maxWidth
          ? img.copyResize(
              decoded,
              width: maxWidth,
              interpolation: img.Interpolation.average,
            )
          : decoded;

      for (final quality in <int>[78, 68, 58]) {
        final encoded = img.encodeJpg(resized, quality: quality);
        final base64Text = base64Encode(encoded);
        if (base64Text.length <= maxBase64Characters) return base64Text;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

Uint8List? decodeReceiptImage(String? base64Text) {
  if (base64Text == null || base64Text.isEmpty) return null;
  try {
    return base64Decode(base64Text);
  } catch (_) {
    return null;
  }
}
