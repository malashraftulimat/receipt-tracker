import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/category.dart';
import '../domain/models/receipt.dart';
import '../domain/models/receipt_filter.dart';
import 'repositories/auth_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/receipt_repository.dart';
import 'repositories/storage_repository.dart';
import 'services/ocr/ocr_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(ref.watch(supabaseClientProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(supabaseClientProvider)),
);

final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => StorageRepository(ref.watch(supabaseClientProvider)),
);

/// ML Kit on mobile, Supabase Edge Function on web / desktop.
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = createOcrService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider); // rebuild on sign-in / sign-out / refresh
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

final userIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

final categoriesProvider = FutureProvider<List<ExpenseCategory>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <ExpenseCategory>[];
  final repository = ref.watch(categoryRepositoryProvider);
  await repository.ensureDefaults();
  return repository.fetchAll();
});

/// Dashboard query state (search / category / month / range / view mode).
class ReceiptFilterController extends Notifier<ReceiptFilter> {
  @override
  ReceiptFilter build() => const ReceiptFilter();

  void setSearch(String value) => state = state.copyWith(search: value);

  void toggleCategory(String? categoryId) => state = state.copyWith(
        categoryId: state.categoryId == categoryId ? null : categoryId,
      );

  void setMonth(DateTime? month) => state = state.copyWith(
        month: month == null ? null : DateTime(month.year, month.month),
        from: null,
        to: null,
      );

  void setRange(DateTime start, DateTime endInclusive) => state = state.copyWith(
        month: null,
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(
          endInclusive.year,
          endInclusive.month,
          endInclusive.day + 1,
        ),
      );

  void clearRange() => state = state.copyWith(month: null, from: null, to: null);

  void setView(ReceiptViewMode view) => state = state.copyWith(view: view);

  void reset() => state = ReceiptFilter(view: state.view);
}

final receiptFilterProvider =
    NotifierProvider<ReceiptFilterController, ReceiptFilter>(
  ReceiptFilterController.new,
);

final receiptsProvider = FutureProvider<List<Receipt>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Receipt>[];
  final filter = ref.watch(receiptFilterProvider);
  return ref.watch(receiptRepositoryProvider).fetch(filter);
});

final receiptByIdProvider = FutureProvider.family<Receipt, String>(
  (ref, id) => ref.watch(receiptRepositoryProvider).getById(id),
);

/// Signed URL for a stored receipt image path.
final signedImageUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref.watch(storageRepositoryProvider).signedUrl(path),
);
