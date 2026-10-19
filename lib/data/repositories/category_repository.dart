import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/category.dart';

class CategoryRepository {
  CategoryRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  Future<List<ExpenseCategory>> fetchAll() async {
    final rows = await _client
        .from('categories')
        .select()
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    return rows.map(ExpenseCategory.fromJson).toList(growable: false);
  }

  /// Seeds the predefined categories for accounts created before the DB trigger
  /// existed (idempotent thanks to the `(user_id, name)` unique constraint).
  Future<void> ensureDefaults() async {
    final rows =
        await _client.from('categories').select('id').limit(1);
    if (rows.isNotEmpty) return;
    try {
      await _client.from('categories').insert(<Map<String, dynamic>>[
        for (final template in ExpenseCategory.templates)
          <String, dynamic>{
            'user_id': _userId,
            ...template.toRow(),
          },
      ]);
    } on PostgrestException catch (error) {
      // Another device seeded the rows first — that is fine.
      if (error.code != '23505') rethrow;
    }
  }

  Future<ExpenseCategory> create({
    required String name,
    required String color,
    required String icon,
  }) async {
    final row = await _client
        .from('categories')
        .insert(<String, dynamic>{
          'user_id': _userId,
          'name': name.trim(),
          'color': color,
          'icon': icon,
          'is_default': false,
          'sort_order': 100,
        })
        .select()
        .single();
    return ExpenseCategory.fromJson(row);
  }

  Future<ExpenseCategory> update(ExpenseCategory category) async {
    final row = await _client
        .from('categories')
        .update(category.toRow())
        .eq('id', category.id)
        .select()
        .single();
    return ExpenseCategory.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }
}
