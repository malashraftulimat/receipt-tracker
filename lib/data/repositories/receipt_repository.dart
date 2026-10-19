import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/models/receipt_filter.dart';

/// Thrown when a receipt with the same barcode already exists.
class DuplicateReceiptException implements Exception {
  DuplicateReceiptException(this.barcode, {this.existingId});

  final String barcode;
  final String? existingId;

  @override
  String toString() => 'DuplicateReceiptException($barcode)';
}

class ReceiptRepository {
  ReceiptRepository(this._client);

  final SupabaseClient _client;

  static const String _selectWithCategory = '*, category:categories(*)';

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  Future<List<Receipt>> fetch(ReceiptFilter filter) async {
    var query = _client.from('receipts').select(_selectWithCategory);

    if (filter.categoryId != null) {
      query = query.eq('category_id', filter.categoryId!);
    }
    final start = filter.rangeStart;
    final end = filter.rangeEnd;
    if (start != null) {
      query = query.gte('purchased_at', start.toUtc().toIso8601String());
    }
    if (end != null) {
      // End is exclusive so a full month / day is included.
      query = query.lt('purchased_at', end.toUtc().toIso8601String());
    }
    if (filter.searchTerm.isNotEmpty) {
      final term = filter.searchTerm.replaceAll(RegExp(r'[,()]'), ' ');
      query = query.or(
        'merchant.ilike.%$term%,note.ilike.%$term%,barcode_id.ilike.%$term%',
      );
    }

    final rows =
        await query.order('purchased_at', ascending: false).limit(1000);
    return rows.map(Receipt.fromJson).toList(growable: false);
  }

  Future<Receipt> getById(String id) async {
    final row = await _client
        .from('receipts')
        .select(_selectWithCategory)
        .eq('id', id)
        .single();
    return Receipt.fromJson(row);
  }

  Future<String?> findIdByBarcode(String barcode) async {
    final rows = await _client
        .from('receipts')
        .select('id')
        .eq('barcode_id', barcode)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  Future<Receipt> create(ReceiptDraft draft, {String? imagePath}) async {
    final barcode = draft.barcodeId?.trim();
    if (barcode != null && barcode.isNotEmpty) {
      final existingId = await findIdByBarcode(barcode);
      if (existingId != null) {
        throw DuplicateReceiptException(barcode, existingId: existingId);
      }
    }

    try {
      final row = await _client
          .from('receipts')
          .insert(<String, dynamic>{
            'user_id': _userId,
            ...draft.toRow(),
            'image_path': imagePath ?? draft.imagePath,
          })
          .select(_selectWithCategory)
          .single();
      return Receipt.fromJson(row);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        // Lost a race against another device: look the existing row up again.
        final existingId =
            barcode == null ? null : await findIdByBarcode(barcode);
        throw DuplicateReceiptException(barcode ?? '', existingId: existingId);
      }
      rethrow;
    }
  }

  Future<Receipt> update(String id, Map<String, dynamic> patch) async {
    final row = await _client
        .from('receipts')
        .update(patch)
        .eq('id', id)
        .select(_selectWithCategory)
        .single();
    return Receipt.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('receipts').delete().eq('id', id);
  }
}
