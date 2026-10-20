import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Native camera on Android / iOS, photo picker fallback on web / desktop.
///
/// The web scanner captures OCR frames from its live `getUserMedia` stream via
/// `CameraFrame`; this picker is only used there when camera access is denied.
class ImageInput {
  const ImageInput._();

  static final ImagePicker _picker = ImagePicker();

  static bool get supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<XFile?> pickReceiptImage({bool forceGallery = false}) {
    return _picker.pickImage(
      source: supportsCamera && !forceGallery
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1800,
      preferredCameraDevice: CameraDevice.rear,
    );
  }
}
