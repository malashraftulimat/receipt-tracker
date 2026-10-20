import 'dart:typed_data';

/// Non-web platforms have no HTML video element to capture from.
bool get isSupported => false;

Future<Uint8List?> capture({
  int maxWidth = 2400,
  double quality = 0.92,
}) async =>
    null;

Future<void> prepareForCapture() async {}

Future<void> focusAt(double x, double y) async {}

Future<Uint8List?> pickFromDeviceCamera() async => null;
