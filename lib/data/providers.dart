import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../domain/models/app_user.dart';
import '../domain/models/category.dart';
import '../domain/models/receipt.dart';
import '../domain/models/receipt_filter.dart';
import 'repositories/auth_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/receipt_repository.dart';
import 'repositories/storage_repository.dart';
import 'services/local_store.dart';
import 'services/ocr/ocr_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

// Repositories resolve the Supabase client lazily so that local mode works
// without ever initialising Supabase.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(),
);

final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => StorageRepository(),
);

bool get _hasOnDeviceOcr =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// ML Kit on mobile, Supabase Edge Function on web / desktop.
/// Local mode on web/desktop has no OCR engine (no server available).
final ocrServiceProvider = Provider<OcrService>((ref) {
  if (AppConfig.isLocal && !_hasOnDeviceOcr) {
    return const UnavailableOcrService(
      'ローカルモードではサーバーOCRを使えません。'
      '「手入力で登録」を使うか、設定から Supabase に接続してください。',
    );
  }
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

/// Holds the signed-in account for on-device (local) mode.
class LocalSessionController extends Notifier<AppUser?> {
  @override
  AppUser? build() => AppConfig.localUser;

  void setUser(AppUser? user) {
    AppConfig.localUser = user;
    if (user != null) LocalStore.instance.useUser(user.id);
    state = user;
  }
}

final localSessionProvider =
    NotifierProvider<LocalSessionController, AppUser?>(
  LocalSessionController.new,
);

final currentUserProvider = Provider<AppUser?>((ref) {
  if (AppConfig.isLocal) return ref.watch(localSessionProvider);

  ref.watch(authStateProvider); // rebuild on sign-in / sign-out / refresh
  final user = ref.watch(supabaseClientProvider).auth.currentUser;
  if (user == null) return null;
  return AppUser(id: user.id, email: user.email ?? '');
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
