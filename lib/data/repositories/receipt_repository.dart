import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/models/receipt_filter.dart';
import '../../domain/models/receipt_item.dart';
import '../services/local_store.dart';

/// Thrown when a receipt with the same barcode already exists.
class DuplicateReceiptException implements Exception {
  DuplicateReceiptException(this.barcode, {this.existingId});

  final String barcode;
  final String? existingId;

  @override
  String toString() => 'DuplicateReceiptException($barcode)';
}

/// Talks to Supabase, or to [LocalStore] when local mode is active.
class ReceiptRepository {
  ReceiptRepository([this._client]);

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const String _selectWithCategory =
      '*, category:categories(*), items:receipt_items(*)';

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  Future<List<Receipt>> fetch(ReceiptFilter filter) async {
    if (AppConfig.isLocal) return LocalStore.instance.fetchReceipts(filter);

    var query = _supabase.from('receipts').select(_selectWithCategory);

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
    if (AppConfig.isLocal) {
      final receipt = await LocalStore.instance.receiptById(id);
      if (receipt == null) throw StateError('レシートが見つかりません');
      return receipt;
    }

    final row = await _supabase
        .from('receipts')
        .select(_selectWithCategory)
        .eq('id', id)
        .single();
    return Receipt.fromJson(row);
  }

  Future<String?> findIdByBarcode(String barcode) async {
    if (AppConfig.isLocal) {
      return LocalStore.instance.findIdByBarcode(barcode);
    }

    final rows = await _supabase
        .from('receipts')
        .select('id')
        .eq('barcode_id', barcode)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  Future<Receipt> create(ReceiptDraft draft, {String? imagePath}) async {
    final barcode = draft.barcodeId?.trim();

    if (AppConfig.isLocal) {
      if (barcode != null && barcode.isNotEmpty) {
        final existingId = await LocalStore.instance.findIdByBarcode(barcode);
        if (existingId != null) {
          throw DuplicateReceiptException(barcode, existingId: existingId);
        }
      }
      return LocalStore.instance.createReceipt(draft, imagePath);
    }

    if (barcode != null && barcode.isNotEmpty) {
      final existingId = await findIdByBarcode(barcode);
      if (existingId != null) {
        throw DuplicateReceiptException(barcode, existingId: existingId);
      }
    }

    try {
      final inserted = await _supabase
          .from('receipts')
          .insert(<String, dynamic>{
            'user_id': _userId,
            ...draft.toRow(),
            'image_path': imagePath ?? draft.imagePath,
          })
          .select('id')
          .single();
      final id = inserted['id'] as String;

      if (draft.items.isNotEmpty) {
        await _supabase.from('receipt_items').insert(<Map<String, dynamic>>[
          for (var i = 0; i < draft.items.length; i++)
            <String, dynamic>{
              ...draft.items[i].toRow(receiptId: id),
              'sort_order': i,
            },
        ]);
      }

      return getById(id);
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

  Future<Receipt> update(
    String id,
    Map<String, dynamic> patch, {
    List<ReceiptItem>? items,
  }) async {
    if (AppConfig.isLocal) {
      return LocalStore.instance.updateReceipt(
        id,
        <String, dynamic>{
          ...patch,
          if (items != null)
            'items': <Map<String, dynamic>>[
              for (var i = 0; i < items.length; i++)
                <String, dynamic>{...items[i].toJson(), 'sort_order': i},
            ],
        },
      );
    }

    await _supabase.from('receipts').update(patch).eq('id', id);

    if (items != null) {
      await _supabase.from('receipt_items').delete().eq('receipt_id', id);
      if (items.isNotEmpty) {
        await _supabase.from('receipt_items').insert(<Map<String, dynamic>>[
          for (var i = 0; i < items.length; i++)
            <String, dynamic>{
              ...items[i].toRow(receiptId: id),
              'sort_order': i,
            },
        ]);
      }
    }

    return getById(id);
  }

  Future<void> delete(String id) async {
    if (AppConfig.isLocal) {
      await LocalStore.instance.deleteReceipt(id);
      return;
    }
    await _supabase.from('receipts').delete().eq('id', id);
  }
}