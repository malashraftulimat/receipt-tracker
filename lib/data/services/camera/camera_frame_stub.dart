import 'dart:typed_data';

/// Non-web platforms have no HTML video element to capture from.
bool get isSupported => false;

Future<Uint8List?> capture({
  int maxWidth = 2000,
  double quality = 0.9,
}) async =>
    null;
