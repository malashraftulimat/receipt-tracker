import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes the export into the app documents folder and returns the path.
Future<String> saveExportedFile(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
