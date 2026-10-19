import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/monthly_budget.dart';
import '../services/local_store.dart';

class BudgetRepository {
  BudgetRepository([this._client]);

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  Future<MonthlyBudget?> fetchMonth(DateTime month) async {
    if (AppConfig.isLocal) return LocalStore.instance.fetchBudget(month);

    final first = DateTime(month.year, month.month, 1);
    final rows = await _supabase
        .from('budgets')
        .select()
        .eq('month', first.toUtc().toIso8601String())
        .limit(1);
    if (rows.isEmpty) return null;
    return MonthlyBudget.fromJson(rows.first);
  }

  Future<MonthlyBudget> save(MonthlyBudget budget) async {
    if (AppConfig.isLocal) return LocalStore.instance.saveBudget(budget);

    final first = DateTime(budget.month.year, budget.month.month, 1);
    final row = await _supabase
        .from('budgets')
        .upsert(
          <String, dynamic>{
            ...budget.toRow(),
            'user_id': _userId,
            'month': first.toUtc().toIso8601String(),
          },
          onConflict: 'user_id,month',
        )
        .select()
        .single();
    return MonthlyBudget.fromJson(row);
  }
}
