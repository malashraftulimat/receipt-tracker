import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/core/config/ai_config.dart';
import 'package:receipt_tracker/core/localization/app_language.dart';
import 'package:receipt_tracker/core/localization/app_localizations.dart';

void main() {
  const en = AppLocalizations(AppLanguage.en);
  const ar = AppLocalizations(AppLanguage.ar);
  const ja = AppLocalizations(AppLanguage.ja);

  test('budget field labels are translated', () {
    expect(en.translate('monthly_income_net'), 'Monthly Income (Net)');
    expect(en.translate('savings_goal'), 'Savings Goal');
    expect(
      en.translate('fixed_expenses_rent_utilities_subscriptions'),
      'Fixed Expenses (rent, utilities, subscriptions)',
    );

    expect(ar.translate('monthly_income_net'), 'الدخل الشهري (الصافي)');
    expect(ar.translate('savings_goal'), 'هدف الادخار');
    expect(
      ar.translate('fixed_expenses_rent_utilities_subscriptions'),
      'المصاريف الثابتة (الإيجار، المرافق، الاشتراكات)',
    );
    expect(ja.translate('savings_goal'), '貯蓄目標');
  });

  test('budget status and pacing messages are localized', () {
    expect(en.translate('budget_not_set'), 'Budget not set');
    expect(en.translate('on_track'), 'On track');
    expect(en.translate('watch_spending_pace'), 'Watch spending pace');
    expect(en.translate('over_budget_2'), 'Over budget');

    expect(
      en.msg(
        'budget.over_plan',
        params: <String, Object?>{
          'amount': '¥1,000',
          'days': 5,
          'daily': '¥200',
        },
      ),
      'You are spending ¥1,000 more than planned. '
      '5 days left; about ¥200 per day.',
    );
    expect(
      en.msg(
        'budget.under_plan',
        params: <String, Object?>{'amount': '¥500', 'goal': '¥30,000'},
      ),
      'You are saving ¥500 compared with the plan. '
      'At this pace you will reach the savings goal of ¥30,000.',
    );
  });

  test('AI unavailable toast is localized', () {
    expect(
      en.translate('the_ai_service_is_getting_ready_please_try_a'),
      'The AI service is getting ready. Please try again in a moment.',
    );
    expect(
      ar.translate('the_ai_service_is_getting_ready_please_try_a'),
      'جاري تجهيز خدمة الذكاء الاصطناعي، يرجى المحاولة بعد لحظات',
    );
    expect(en.translate('ai_error_details'), 'AI error details');
    expect(ar.translate('ai_error_details'), 'تفاصيل خطأ الذكاء الاصطناعي');
  });

  test('Gemini model configuration uses current supported names', () {
    expect(kGeminiReceiptModel, 'gemini-3.1-flash-lite');
    expect(kGeminiReceiptFallbackModels, contains('gemini-3.5-flash-lite'));
    expect(kGeminiReceiptFallbackModels, contains('gemini-3.6-flash'));
    expect(kGeminiReceiptFallbackModels, isNot(contains('gemini-2.0-flash')));
    expect(kGeminiReceiptFallbackModels, isNot(contains('gemini-1.5-flash')));
    expect(kGeminiReceiptFallbackModels, isNot(contains('gemini-2.5-flash')));
  });

  test('Gemini key comes only from the GEMINI_API_KEY build define', () {
    final override = const String.fromEnvironment('GEMINI_API_KEY').trim();
    final key = geminiApiKeyOrNull();
    expect(hasGeminiApiKey(), override.isNotEmpty);
    expect(key, override.isEmpty ? isNull : key);
  });

  test('category screen messages are localized', () {
    expect(
      en.msg('record.delete_named', params: <String, Object?>{'name': '食費'}),
      'Delete “食費”.',
    );
    expect(
      en.msg(
        'error.categories_load_failed',
        params: <String, Object?>{'error': 'network error'},
      ),
      'Could not load categories\nnetwork error',
    );
    expect(
      en.msg('error.save_failed', params: <String, Object?>{'error': 'offline'}),
      'Could not save: offline',
    );
    expect(
      ar.msg('error.delete_failed', params: <String, Object?>{'error': 'offline'}),
      'تعذّر الحذف: offline',
    );
  });

  test('language switching strings are localized', () {
    expect(en.translate('change_language'), 'Change language');
    expect(ar.translate('change_language'), 'تغيير اللغة');
    expect(
      en.translate('settings.language_help'),
      contains('detected automatically'),
    );
  });

  test('plural forms follow CLDR for English and Arabic', () {
    expect(en.msg('count.items', count: 1), '1 item');
    expect(en.msg('count.items', count: 5), '5 items');
    expect(ar.msg('count.items', count: 0), 'لا عناصر');
    expect(ar.msg('count.items', count: 1), 'عنصر واحد');
    expect(ar.msg('count.items', count: 2), 'عنصران');
    for (final part in <String>['zero', 'one', 'two', 'few', 'many', 'other']) {
      expect(ja.translate('count.items.$part'), contains('{count}'));
    }
  });

  test('seeded category names translate without touching custom names', () {
    expect(en.translate('食費'), 'Food');
    expect(ar.translate('食費'), 'الطعام');
    expect(en.translate('My custom category'), 'My custom category');
  });

  group('AppLanguage detection', () {
    test('parses plain and region-tagged codes', () {
      expect(AppLanguage.tryParse('ja'), AppLanguage.ja);
      expect(AppLanguage.tryParse('en'), AppLanguage.en);
      expect(AppLanguage.tryParse('AR'), AppLanguage.ar);
      expect(AppLanguage.tryParse('ja-JP'), AppLanguage.ja);
      expect(AppLanguage.tryParse('en_US'), AppLanguage.en);
      expect(AppLanguage.tryParse('ar-EG'), AppLanguage.ar);
      expect(AppLanguage.tryParse('fr'), isNull);
      expect(AppLanguage.tryParse(''), isNull);
      expect(AppLanguage.tryParse(null), isNull);
    });

    test('unsupported languages fall back to Japanese', () {
      expect(AppLanguage.fromCode('de-DE'), AppLanguage.ja);
      expect(AppLanguage.fromCode(null), AppLanguage.ja);
    });

    test('fromLocales picks the first supported locale', () {
      expect(
        AppLanguage.fromLocales(const <Locale>[Locale('fr'), Locale('en', 'US')]),
        AppLanguage.en,
      );
      expect(
        AppLanguage.fromLocales(const <Locale>[Locale('ar')]),
        AppLanguage.ar,
      );
      expect(AppLanguage.fromLocales(const <Locale>[Locale('de')]), isNull);
      expect(AppLanguage.fromLocales(const <Locale>[]), isNull);
    });
  });
}
