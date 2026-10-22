import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/receipt.dart';
import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as saver;

/// CSV export that opens cleanly in Excel / Numbers / Google Sheets.
///
/// The file is UTF-8 with a BOM so Japanese characters are not garbled.
class ExportService {
  const ExportService._();

  static const List<String> header = <String>[
    '日付',
    '時刻',
    '店舗',
    'カテゴリ',
    '合計(税込)',
    '小計(税抜)',
    '消費税8%',
    '消費税10%',
    '8%対象商品計',
    '10%対象商品計',
    '支払期限',
    'ポイント種別',
    'ポイント',
    'バーコード',
    'メモ',
  ];

  static String buildCsv(List<Receipt> receipts) {
    final rows = <List<String>>[header];
    for (final receipt in receipts) {
      final date = receipt.purchasedAt;
      rows.add(<String>[
        '${date.year}-${_two(date.month)}-${_two(date.day)}',
        '${_two(date.hour)}:${_two(date.minute)}',
        receipt.displayMerchant,
        receipt.displayCategory,
        _amount(receipt.totalAmount),
        _amount(receipt.subtotalAmount),
        _amount(receipt.tax8Amount),
        _amount(receipt.tax10Amount),
        _amount(receipt.tax8ItemsTotal),
        _amount(receipt.tax10ItemsTotal),
        receipt.dueDate == null
            ? ''
            : '${receipt.dueDate!.year}-${_two(receipt.dueDate!.month)}-'
                '${_two(receipt.dueDate!.day)}',
        receipt.pointBrand ?? '',
        _amount(receipt.pointAmount),
        receipt.barcodeId ?? '',
        receipt.note ?? '',
      ]);
    }
    return rows.map((row) => row.map(_escape).join(',')).join('\r\n');
  }

  /// Saves the CSV and returns the filename / path shown to the user.
  static Future<String> export(
    List<Receipt> receipts, {
    required String filename,
  }) async {
    final csv = buildCsv(receipts);
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
    return saver.saveExportedFile(bytes, filename, 'text/csv;charset=utf-8');
  }

  static String filenameForMonth(DateTime month) =>
      'receipts_${month.year}-${_two(month.month)}.csv';

  static String allFilename() {
    final now = DateTime.now();
    return 'receipts_all_${now.year}${_two(now.month)}${_two(now.day)}.csv';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _amount(num? value) => value == null ? '' : value.toString();

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
