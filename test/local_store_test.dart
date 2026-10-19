import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/local_store.dart';
import 'package:receipt_tracker/domain/models/receipt_draft.dart';
import 'package:receipt_tracker/domain/models/receipt_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalStore.instance.resetCacheForTests();
    await LocalStore.instance.clearAll();
  });

  test('seeds the eight default categories', () async {
    await LocalStore.instance.seedDefaults();
    final categories = await LocalStore.instance.fetchCategories();
    expect(categories.length, 8);
    expect(categories.first.name, '食費');
    expect(categories.map((c) => c.name), contains('娯楽'));

    // Idempotent.
    await LocalStore.instance.seedDefaults();
    expect((await LocalStore.instance.fetchCategories()).length, 8);
  });

  test('creates, filters, updates and deletes receipts', () async {
    await LocalStore.instance.seedDefaults();
    final categories = await LocalStore.instance.fetchCategories();
    final groceries = categories.first;

    final ion = await LocalStore.instance.createReceipt(
      ReceiptDraft(
        merchant: 'イオン',
        purchasedAt: DateTime(2026, 10, 19, 12),
        totalAmount: 1200,
        categoryId: groceries.id,
        note: '週末の買い物',
      ),
      null,
    );
    await LocalStore.instance.createReceipt(
      ReceiptDraft(
        merchant: 'サイゼリヤ',
        purchasedAt: DateTime(2026, 9, 2),
        totalAmount: 900,
      ),
      null,
    );

    expect(ion.category?.name, '食費');

    final all =
        await LocalStore.instance.fetchReceipts(const ReceiptFilter());
    expect(all.length, 2);
    expect(all.first.merchant, 'イオン'); // newest first

    final october = await LocalStore.instance.fetchReceipts(
      ReceiptFilter(month: DateTime(2026, 10)),
    );
    expect(october.length, 1);
    expect(october.single.merchant, 'イオン');

    final byCategory = await LocalStore.instance.fetchReceipts(
      ReceiptFilter(categoryId: groceries.id),
    );
    expect(byCategory.length, 1);

    final bySearch = await LocalStore.instance.fetchReceipts(
      const ReceiptFilter(search: 'サイゼ'),
    );
    expect(bySearch.single.merchant, 'サイゼリヤ');

    final updated = await LocalStore.instance.updateReceipt(
      ion.id,
      <String, dynamic>{'total_amount': 1500, 'note': '修正済み'},
    );
    expect(updated.totalAmount, 1500);
    expect(updated.note, '修正済み');
    expect(updated.category?.name, '食費');

    await LocalStore.instance.deleteReceipt(ion.id);
    final remaining =
        await LocalStore.instance.fetchReceipts(const ReceiptFilter());
    expect(remaining.length, 1);
    expect(remaining.single.merchant, 'サイゼリヤ');
  });

  test('barcode lookup reports duplicates', () async {
    final receipt = await LocalStore.instance.createReceipt(
      ReceiptDraft(barcodeId: '4901234567894', totalAmount: 100),
      null,
    );
    expect(
      await LocalStore.instance.findIdByBarcode('4901234567894'),
      receipt.id,
    );
    expect(await LocalStore.instance.findIdByBarcode('0000000000000'), isNull);
  });

  test('category deletion detaches receipts', () async {
    await LocalStore.instance.seedDefaults();
    final categoryId = await LocalStore.instance.createCategory(
      name: '交際費',
      color: '#8D6E63',
      icon: 'cafe',
    );
    await LocalStore.instance.createReceipt(
      ReceiptDraft(merchant: 'カフェ', totalAmount: 600, categoryId: categoryId.id),
      null,
    );

    await LocalStore.instance.deleteCategory(categoryId.id);
    final remaining =
        await LocalStore.instance.fetchReceipts(const ReceiptFilter());
    expect(remaining.single.categoryId, isNull);
    expect((await LocalStore.instance.fetchCategories()).length, 8);
  });
}