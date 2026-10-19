import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScanMode { barcode, ocr, auto }

extension ScanModeLabels on ScanMode {
  String get label {
    switch (this) {
      case ScanMode.barcode:
        return 'バーコード';
      case ScanMode.ocr:
        return 'レシートOCR';
      case ScanMode.auto:
        return '自動';
    }
  }

  String get hint {
    switch (this) {
      case ScanMode.barcode:
        return 'JAN-13 / Code 128 を枠内に合わせてください';
      case ScanMode.ocr:
        return 'レシート全体が入るように撮影してください';
      case ScanMode.auto:
        return 'バーコードを検出し、続けてレシート文字も読み取ります';
    }
  }
}

/// Transient scanner state: selected mode + the last detected barcode.
class ScanSession {
  const ScanSession({
    this.mode = ScanMode.barcode,
    this.barcode,
    this.duplicateOf,
  });

  final ScanMode mode;
  final String? barcode;

  /// Set when the detected barcode already exists in the database.
  final String? duplicateOf;

  ScanSession copyWith({
    ScanMode? mode,
    String? barcode,
    bool clearBarcode = false,
    String? duplicateOf,
    bool clearDuplicate = false,
  }) {
    return ScanSession(
      mode: mode ?? this.mode,
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      duplicateOf: clearDuplicate ? null : (duplicateOf ?? this.duplicateOf),
    );
  }
}

class ScanSessionController extends Notifier<ScanSession> {
  @override
  ScanSession build() => const ScanSession();

  void setMode(ScanMode mode) =>
      state = ScanSession(mode: mode, barcode: state.barcode);

  void setBarcode(String barcode) => state = state.copyWith(barcode: barcode);

  void setDuplicateOf(String? receiptId) => state = receiptId == null
      ? state.copyWith(clearDuplicate: true)
      : state.copyWith(duplicateOf: receiptId);

  void clearBarcode() => state =
      state.copyWith(clearBarcode: true, clearDuplicate: true);

  void reset() => state = ScanSession(mode: state.mode);
}

final scanSessionProvider =
    NotifierProvider<ScanSessionController, ScanSession>(
  ScanSessionController.new,
);
