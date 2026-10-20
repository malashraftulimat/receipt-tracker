import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// `getUserMedia` is available on all browsers that support Flutter Web.
bool get isSupported => !web.window.navigator.mediaDevices.isUndefinedOrNull;

/// Capture the current frame of the live scanner preview.
///
/// `mobile_scanner` attaches the camera stream to an `<video>` element inside
/// its platform view. Drawing that element onto a canvas gives us a full
/// resolution JPEG without touching the camera a second time.
Future<Uint8List?> capture({
  int maxWidth = 2400,
  double quality = 0.92,
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

/// Applies the best resolution and continuous autofocus the active camera
/// track supports.
///
/// `mobile_scanner` does not expose its `MediaStreamTrack`, so we read it from
/// `HTMLVideoElement.srcObject`. Every constraint is feature-detected and all
/// failures are ignored: focus tuning must never stop barcode/OCR scanning.
Future<void> prepareForCapture() async {
  if (!isSupported) return;

  for (var attempt = 0; attempt < 12; attempt++) {
    final track = _videoTrack(_activeVideoElement());
    if (track != null) {
      final focusModes = _focusModes(track);
      await _applyConstraints(track, <String, Object?>{
        'width': <String, Object>{'ideal': 1920},
        'height': <String, Object>{'ideal': 1080},
        if (focusModes.contains('continuous'))
          'focusMode': <String, Object>{'ideal': 'continuous'},
      });
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
}

/// Re-focuses the camera at a point in the preview.
///
/// [x] and [y] are normalised (0..1) coordinates inside the video element.
/// Uses single-shot or manual+continuous autofocus when the device exposes
/// those modes, and pointsOfInterest only when the track reports support.
Future<void> focusAt(double x, double y) async {
  if (!isSupported) return;

  final track = _videoTrack(_activeVideoElement());
  if (track == null) return;

  final focusModes = _focusModes(track);
  final supportsPointsOfInterest =
      _capabilities(track)?.pointsOfInterest != null;
  final pointX = x.clamp(0.0, 1.0);
  final pointY = y.clamp(0.0, 1.0);

  Future<void> apply(String mode, {bool withPoint = false}) {
    return _applyConstraints(track, <String, Object?>{
      'focusMode': <String, Object>{'ideal': mode},
      if (withPoint && supportsPointsOfInterest)
        'pointsOfInterest': <Map<String, double>>[
          <String, double>{'x': pointX, 'y': pointY},
        ],
    });
  }

  try {
    if (focusModes.contains('single-shot')) {
      await apply('single-shot', withPoint: true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (focusModes.contains('continuous')) {
        await apply('continuous');
      }
    } else if (focusModes.contains('manual') &&
        focusModes.contains('continuous')) {
      await apply('manual', withPoint: true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await apply('continuous');
    } else if (focusModes.contains('continuous')) {
      await apply('continuous', withPoint: true);
    }
  } catch (_) {
    // Browsers reject unsupported constraint combinations. Keep scanning.
  }
}

/// Opens the platform camera through
/// `<input type="file" accept="image/*" capture="environment">`.
///
/// This is the iOS Safari path: it does not require focus constraints and the
/// selected photo is only read into memory. Returns `null` when the user
/// cancels or the browser cannot read the file.
Future<Uint8List?> pickFromDeviceCamera() async {
  try {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*'
      ..capture = 'environment'
      ..style.display = 'none';

    final completer = Completer<Uint8List?>();

    void finish(JSAny? _) {
      final file = input.files?.item(0);
      input.remove();
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      file.arrayBuffer().toDart.then((buffer) {
        if (!completer.isCompleted) {
          completer.complete(Uint8List.view(buffer.toDart));
        }
      }).catchError((Object _) {
        if (!completer.isCompleted) completer.complete(null);
      });
    }

    input.addEventListener('change', finish.toJS);
    input.addEventListener('cancel', finish.toJS);

    web.document.body?.appendChild(input);
    input.click();

    return await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => null,
    );
  } catch (_) {
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

/// Typed wrappers around the parts of MediaStreamTrack we need. The web
/// package types the constraint dictionaries as `JSAny`, so using a small
/// JSObject view keeps unsupported focus properties optional.
_FocusTrack? _videoTrack(web.HTMLVideoElement? video) {
  try {
    final source = video?.srcObject;
    if (source == null) return null;
    final tracks = _MediaStreamSource._(source).getVideoTracks().toDart;
    if (tracks.isEmpty) return null;
    return _FocusTrack._(tracks.first);
  } catch (_) {
    return null;
  }
}

_FocusCapabilities? _capabilities(_FocusTrack track) {
  try {
    return _FocusCapabilities._(track.getCapabilities());
  } catch (_) {
    return null;
  }
}

Set<String> _focusModes(_FocusTrack track) {
  try {
    final modes = _capabilities(track)?.focusMode;
    if (modes == null) return const <String>{};
    return modes.toDart.map((mode) => mode.toDart).toSet();
  } catch (_) {
    return const <String>{};
  }
}

Future<void> _applyConstraints(
  _FocusTrack track,
  Map<String, Object?> constraints,
) async {
  try {
    await track
        .applyConstraints(constraints.jsify() as JSObject)
        .toDart
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    // Constraint unsupported / camera busy: silently keep the current stream.
  }
}

extension type _MediaStreamSource._(JSObject _) implements JSObject {
  external JSArray<JSObject> getVideoTracks();
}

extension type _FocusTrack._(JSObject _) implements JSObject {
  external JSObject getCapabilities();
  external JSPromise<JSAny?> applyConstraints(JSObject constraints);
}

extension type _FocusCapabilities._(JSObject _) implements JSObject {
  external JSArray<JSString>? get focusMode;
  external JSObject? get pointsOfInterest;
}
