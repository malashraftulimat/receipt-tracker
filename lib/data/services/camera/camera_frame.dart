import 'dart:typed_data';

import 'camera_frame_stub.dart'
    if (dart.library.js_interop) 'camera_frame_web.dart' as platform;

/// Grabs a still JPEG frame from the live HTML5 `<video>` element that
/// `mobile_scanner` renders on Flutter Web.
///
/// The live preview and the barcode decoder share the same `getUserMedia`
/// stream, so OCR can use the exact frame the user sees without opening a
/// second camera stream or asking for permission again.
///
/// On Android / iOS this always returns `null`; the scanner uses
/// `image_picker` (ML Kit path) there instead.
class CameraFrame {
  const CameraFrame._();

  /// Whether the current platform can capture a frame from the live preview.
  static bool get isSupported => platform.isSupported;

  /// Captures the current video frame as JPEG bytes.
  ///
  /// Returns `null` when there is no active video element, e.g. the camera is
  /// still starting or permission was denied.
  static Future<Uint8List?> capture({
    int maxWidth = 2000,
    double quality = 0.9,
  }) =>
      platform.capture(maxWidth: maxWidth, quality: quality);
}
