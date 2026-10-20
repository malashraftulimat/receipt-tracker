import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// `getUserMedia` is available on all browsers that support Flutter Web.
bool get isSupported =>
    !web.window.navigator.mediaDevices.isUndefinedOrNull;

/// Capture the current frame of the live scanner preview.
///
/// `mobile_scanner` attaches the camera stream to an `<video>` element inside
/// its platform view. Drawing that element onto a canvas gives us a full
/// resolution JPEG without touching the camera a second time.
Future<Uint8List?> capture({
  int maxWidth = 2000,
  double quality = 0.9,
}) async {
  try {
    final video = _activeVideoElement();
    if (video == null) return null;

    final sourceWidth = video.videoWidth;
    final sourceHeight = video.videoHeight;
    if (sourceWidth <= 0 || sourceHeight <= 0) return null;

    final scale = math.min(1.0, maxWidth / sourceWidth);
    final width = math.max(1, (sourceWidth * scale).round());
    final height = math.max(1, (sourceHeight * scale).round());

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;

    final context = canvas.getContext('2d');
    if (context == null) return null;
    final ctx = context as web.CanvasRenderingContext2D;

    ctx.drawImage(video, 0, 0, width, height);

    final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;

    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    // No frame yet / browser refused canvas access: use the photo picker.
    return null;
  }
}

web.HTMLVideoElement? _activeVideoElement() {
  final videos = web.document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    final node = videos.item(i);
    if (node == null) continue;

    final video = node as web.HTMLVideoElement;
    if (video.videoWidth > 0 && video.videoHeight > 0) {
      return video;
    }
  }
  return null;
}
