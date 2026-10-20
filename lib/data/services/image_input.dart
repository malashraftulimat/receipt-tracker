import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';

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
    // Local mode keeps the photo in localStorage, so downscale a bit more.
    final local = AppConfig.isLocal;
    return _picker.pickImage(
      source: supportsCamera && !forceGallery
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: local ? 72 : 92,
      maxWidth: local ? 1500 : 2400,
      preferredCameraDevice: CameraDevice.rear,
    );
  }
}
