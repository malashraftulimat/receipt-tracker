import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/core/config/ai_config.dart';
import 'package:receipt_tracker/core/localization/app_language.dart';
import 'package:receipt_tracker/core/localization/app_localizations.dart';

void main() {
  const en = AppLocalizations(AppLanguage.en);
  const ar = AppLocalizations(AppLanguage.ar);
  const ja = AppLocalizations(AppLanguage.ja);

  test('budget field labels are translated', () {
    expect(en.translate('月収（手取り）'), 'Monthly Income (Net)');
    expect(en.translate('貯蓄目標'), 'Savings Goal');
    expect(
      en.translate('固定費（家賃・光熱費・サブスク）'),
      'Fixed Expenses (rent, utilities, subscriptions)',
    );

    expect(ar.translate('月収（手取り）'), 'الدخل الشهري (الصافي)');
    expect(ar.translate('貯蓄目標'), 'هدف الادخار');
    expect(
      ar.translate('固定費（家賃・光熱費・サブスク）'),
      'المصاريف الثابتة (الإيجار، المرافق، الاشتراكات)',
    );
    expect(ja.translate('貯蓄目標'), '貯蓄目標');
  });

  test('budget status and pacing messages are localized', () {
    expect(en.translate('予算未設定'), 'Budget not set');
    expect(en.translate('順調'), 'On track');
    expect(en.translate('ペース注意'), 'Watch spending pace');
    expect(en.translate('予算オーバー'), 'Over budget');

    expect(
      en.translate(
        '計画より ¥1,000 多く使っています。残り 5 日、1日 ¥200 が目安です。',
      ),
      'You are spending ¥1,000 more than planned.\n'
      '5 days left; about ¥200 per day.',
    );
    expect(
      en.translate(
        '計画より ¥500 節約できています。このペースなら貯蓄目標 ¥30,000 に届きます。',
      ),
      'You are saving ¥500 compared with the plan.\n'
      'At this pace you will reach the savings goal of ¥30,000.',
    );
  });

  test('AI unavailable toast is localized', () {
    expect(
      en.translate('AIサービスを準備しています。しばらくしてからお試しください。'),
      'The AI service is getting ready. Please try again in a moment.',
    );
    expect(
      ar.translate('AIサービスを準備しています。しばらくしてからお試しください。'),
      'جاري تجهيز خدمة الذكاء الاصطناعي، يرجى المحاولة بعد لحظات',
    );
    expect(en.translate('AIエラーの詳細'), 'AI error details');
    expect(ar.translate('AIエラーの詳細'), 'تفاصيل خطأ الذكاء الاصطناعي');
  });

  test('Gemini model configuration uses current supported names', () {
    expect(kGeminiReceiptModel, 'gemini-3.1-flash-lite');
    expect(kGeminiReceiptFallbackModels, contains('gemini-flash-lite-latest'));
    expect(kGeminiReceiptFallbackModels, contains('gemini-3.6-flash'));
    expect(kGeminiReceiptFallbackModels, isNot(contains('gemini-2.0-flash')));
    expect(kGeminiReceiptFallbackModels, isNot(contains('gemini-1.5-flash')));
    expect(kGeminiReceiptFallbackModels, isNot(contains('gemini-2.5-flash')));
  });

  test('Gemini key resolution works without Firebase being initialized', () {
    // The key itself is supplied by the build (dart-define) or a bundled
    // local secret, so it may legitimately be absent in CI.
    expect(geminiApiKeyOrNull, returnsNormally);
    final key = geminiApiKeyOrNull();
    expect(key == null || key.isNotEmpty, isTrue);
    expect(hasGeminiApiKey(), key != null);
  });

  test('category screen messages are localized', () {
    expect(en.translate('「食費」を削除します。'), 'Delete “食費”.');
    expect(
      en.translate('カテゴリを読み込めませんでした\nnetwork error'),
      'Could not load categories\nnetwork error',
    );
    expect(en.translate('保存に失敗しました: offline'), 'Could not save: offline');
    expect(ar.translate('削除に失敗しました: offline'), 'تعذّر الحذف: offline');
  });
}
