import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Camera on Android / iOS, gallery picker on web & desktop.
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
      imageQuality: 92,
      maxWidth: 2400,
      preferredCameraDevice: CameraDevice.rear,
    );
  }
}
