import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'translations_ar.dart';
import 'translations_en.dart';

const List<Locale> kSupportedAppLocales = <Locale>[
  Locale('ja'),
  Locale('en'),
  Locale('ar'),
];

/// Small, dependency-free localization layer for the app's existing Japanese
/// string literals. English / Arabic dictionaries are keyed by the Japanese
/// source, and a few regex rules cover dynamic counts and formatted amounts.
class AppLocalizations {
  const AppLocalizations(this.language);

  final AppLanguage language;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(AppLanguage.ja);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String translate(String source) {
    if (language == AppLanguage.ja) return source;

    final dictionary =
        language == AppLanguage.en ? kEnglishTranslations : kArabicTranslations;
    final exact = dictionary[source];
    if (exact != null) return exact;

    final rules = language == AppLanguage.en ? _englishRules : _arabicRules;
    for (final rule in rules) {
      final match = rule.pattern.firstMatch(source);
      if (match != null) return rule.build(match);
    }

    return source;
  }
}

class _DynamicRule {
  const _DynamicRule(this.pattern, this.build);

  final RegExp pattern;
  final String Function(RegExpMatch match) build;
}

final List<_DynamicRule> _englishRules = <_DynamicRule>[
  _DynamicRule(RegExp(r'^(\d+)件 / (\d+)件$'), (m) => '${m[1]} / ${m[2]} items'),
  _DynamicRule(RegExp(r'^(\d+)件$'), (m) {
    final count = int.tryParse(m[1] ?? '') ?? 0;
    return '$count ${count == 1 ? 'item' : 'items'}';
  }),
  _DynamicRule(RegExp(r'^(\d+)枚$'), (m) {
    final count = int.tryParse(m[1] ?? '') ?? 0;
    return '$count ${count == 1 ? 'photo' : 'photos'}';
  }),
  _DynamicRule(RegExp(r'^(\d+)行$'), (m) => '${m[1]} lines'),
  _DynamicRule(RegExp(r'^(\d+) 行$'), (m) => '${m[1]} lines'),
  _DynamicRule(RegExp(r'^(\d+) 行を表示$'), (m) => 'Show ${m[1]} lines'),
  _DynamicRule(RegExp(r'^(\d+)日超過$'), (m) => '${m[1]} days overdue'),
  _DynamicRule(RegExp(r'^あと(\d+)日$'), (m) => 'in ${m[1]} days'),
  _DynamicRule(RegExp(r'^(\d+)日$'), (m) => '${m[1]} days'),
  _DynamicRule(RegExp(r'^取り込み済み: (\d+) 枚$'), (m) => 'Captured: ${m[1]} photos'),
  _DynamicRule(RegExp(r'^(\d+)枚目を読み取りました。続きを撮影してください$'),
      (m) => 'Photo ${m[1]} captured. Continue with the next part.'),
  _DynamicRule(RegExp(r'^「(.+)」を保存しました$'), (m) => 'Saved “${m[1]}”'),
  _DynamicRule(RegExp(r'^「(.+)」を削除します。$'), (m) => 'Delete “${m[1]}”.'),
  _DynamicRule(RegExp(r'^CSVを書き出しました: (.+)$'), (m) => 'CSV exported: ${m[1]}'),
  _DynamicRule(RegExp(r'^書き出しに失敗しました: (.+)$'), (m) => 'Export failed: ${m[1]}'),
  _DynamicRule(RegExp(r'^保存に失敗しました: (.+)$'), (m) => 'Could not save: ${m[1]}'),
  _DynamicRule(
      RegExp(r'^削除に失敗しました: (.+)$'), (m) => 'Could not delete: ${m[1]}'),
  _DynamicRule(RegExp(r'^カテゴリを読み込めませんでした\n(.+)$'),
      (m) => 'Could not load categories\n${m[1]}'),
  _DynamicRule(RegExp(r'^ブラウザOCRでエラーが発生しました: (.+)$'),
      (m) => 'Browser OCR error: ${m[1]}'),
  _DynamicRule(
      RegExp(r'^(.+)に失敗しました: (.+)$'), (m) => '${m[1]} failed: ${m[2]}'),
  _DynamicRule(RegExp(r'^失敗しました: (.+)$'), (m) => 'Failed: ${m[1]}'),
  _DynamicRule(RegExp(r'^(.+)を読み込めませんでした\n(.+)$'),
      (m) => 'Could not load ${m[1]}\n${m[2]}'),
  _DynamicRule(RegExp(r'^集計を読み込めませんでした\n(.+)$'),
      (m) => 'Could not load analytics\n${m[1]}'),
  _DynamicRule(RegExp(r'^読み込めませんでした\n(.+)$'), (m) => 'Could not load\n${m[1]}'),
  _DynamicRule(RegExp(r'^支払期限 (.+)$'), (m) => 'Due date ${m[1]}'),
  _DynamicRule(RegExp(r'^リマインダー: (.+)$'), (m) => 'Reminder: ${m[1]}'),
  _DynamicRule(RegExp(r'^更新: (.+)$'), (m) => 'Updated: ${m[1]}'),
  _DynamicRule(RegExp(r'^登録: (.+)$'), (m) => 'Created: ${m[1]}'),
  _DynamicRule(RegExp(r'^今日 (.+)$'), (m) => 'Today ${m[1]}'),
  _DynamicRule(RegExp(r'^1日 (.+)$'), (m) => 'Per day ${m[1]}'),
  _DynamicRule(RegExp(r'^貯蓄 (.+)%$'), (m) => 'Savings ${m[1]}%'),
  _DynamicRule(RegExp(r'^税額合計 (.+)$'), (m) => 'Total tax ${m[1]}'),
  _DynamicRule(RegExp(r'^明細 (.+)$'), (m) => 'Items ${m[1]}'),
  _DynamicRule(RegExp(r'^支出 (.+) / 自由枠 (.+)$'),
      (m) => 'Spent ${m[1]} / available ${m[2]}'),
  _DynamicRule(
      RegExp(r'^先月より (.+)$'), (m) => 'Compared with last month: ${m[1]}'),
  _DynamicRule(RegExp(r'^予算を超えています。残り日数は (\d+) 日です。$'),
      (m) => 'Over budget. ${m[1]} days remaining.'),
  _DynamicRule(RegExp(r'^残り (\d+) 日、1日 (.+) が目安です。$'),
      (m) => '${m[1]} days left; about ${m[2]} per day.'),
  _DynamicRule(
      RegExp(r'^計画より (.+) 多く使っています。残り (\d+) 日、1日 (.+) が目安です。$'),
      (m) =>
          'You are spending ${m[1]} more than planned.\n${m[2]} days left; about ${m[3]} per day.'),
  _DynamicRule(
      RegExp(r'^計画より (.+) 節約できています。このペースなら貯蓄目標 (.+) に届きます。$'),
      (m) =>
          'You are saving ${m[1]} compared with the plan.\nAt this pace you will reach the savings goal of ${m[2]}.'),
  _DynamicRule(RegExp(r'^計画より (.+) 多く使っています。$'),
      (m) => 'You are spending ${m[1]} more than planned.'),
  _DynamicRule(RegExp(r'^計画より (.+) 節約できています。$'),
      (m) => 'You are saving ${m[1]} compared with the plan.'),
  _DynamicRule(RegExp(r'^このペースなら貯蓄目標 (.+) に届きます。$'),
      (m) => 'At this pace you will reach the savings goal of ${m[1]}.'),
  _DynamicRule(RegExp(r'^小計 \+ 消費税 = (.+) と合計 (.+) が一致しません。$'),
      (m) => 'Subtotal + tax = ${m[1]} does not match total ${m[2]}.'),
  _DynamicRule(RegExp(r'^明細合計と合計が一致しません（差額 (.+)）$'),
      (m) => 'Item total does not match receipt total (difference ${m[1]}).'),
  _DynamicRule(RegExp(r'^明細合計 (.+) は合計と一致しています$'),
      (m) => 'Item total ${m[1]} matches the receipt total.'),
];

final List<_DynamicRule> _arabicRules = <_DynamicRule>[
  _DynamicRule(RegExp(r'^(\d+)件 / (\d+)件$'), (m) => '${m[1]} / ${m[2]} عناصر'),
  _DynamicRule(RegExp(r'^(\d+)件$'), (m) {
    final count = int.tryParse(m[1] ?? '') ?? 0;
    return '$count ${count == 1 ? 'عنصر' : 'عناصر'}';
  }),
  _DynamicRule(RegExp(r'^(\d+)枚$'), (m) {
    final count = int.tryParse(m[1] ?? '') ?? 0;
    return '$count ${count == 1 ? 'صورة' : 'صور'}';
  }),
  _DynamicRule(RegExp(r'^(\d+)行$'), (m) => '${m[1]} سطر'),
  _DynamicRule(RegExp(r'^(\d+) 行$'), (m) => '${m[1]} سطر'),
  _DynamicRule(RegExp(r'^(\d+) 行を表示$'), (m) => 'عرض ${m[1]} سطر'),
  _DynamicRule(RegExp(r'^(\d+)日超過$'), (m) => 'متأخر ${m[1]} يوم'),
  _DynamicRule(RegExp(r'^あと(\d+)日$'), (m) => 'خلال ${m[1]} يوم'),
  _DynamicRule(RegExp(r'^(\d+)日$'), (m) => '${m[1]} يوم'),
  _DynamicRule(RegExp(r'^取り込み済み: (\d+) 枚$'), (m) => 'تم الالتقاط: ${m[1]} صور'),
  _DynamicRule(RegExp(r'^(\d+)枚目を読み取りました。続きを撮影してください$'),
      (m) => 'تم التقاط الصورة ${m[1]}. تابع الجزء التالي.'),
  _DynamicRule(RegExp(r'^「(.+)」を保存しました$'), (m) => 'تم حفظ «${m[1]}»'),
  _DynamicRule(RegExp(r'^「(.+)」を削除します。$'), (m) => 'حذف «${m[1]}».'),
  _DynamicRule(RegExp(r'^CSVを書き出しました: (.+)$'), (m) => 'تم تصدير CSV: ${m[1]}'),
  _DynamicRule(RegExp(r'^書き出しに失敗しました: (.+)$'), (m) => 'فشل التصدير: ${m[1]}'),
  _DynamicRule(RegExp(r'^保存に失敗しました: (.+)$'), (m) => 'تعذّر الحفظ: ${m[1]}'),
  _DynamicRule(RegExp(r'^削除に失敗しました: (.+)$'), (m) => 'تعذّر الحذف: ${m[1]}'),
  _DynamicRule(
      RegExp(r'^カテゴリを読み込めませんでした\n(.+)$'), (m) => 'تعذّر تحميل الفئات\n${m[1]}'),
  _DynamicRule(RegExp(r'^ブラウザOCRでエラーが発生しました: (.+)$'),
      (m) => 'خطأ في OCR بالمتصفح: ${m[1]}'),
  _DynamicRule(RegExp(r'^(.+)に失敗しました: (.+)$'), (m) => 'فشل ${m[1]}: ${m[2]}'),
  _DynamicRule(RegExp(r'^失敗しました: (.+)$'), (m) => 'فشل: ${m[1]}'),
  _DynamicRule(RegExp(r'^(.+)を読み込めませんでした\n(.+)$'),
      (m) => 'تعذّر تحميل ${m[1]}\n${m[2]}'),
  _DynamicRule(RegExp(r'^集計を読み込めませんでした\n(.+)$'),
      (m) => 'تعذّر تحميل التحليلات\n${m[1]}'),
  _DynamicRule(RegExp(r'^読み込めませんでした\n(.+)$'), (m) => 'تعذّر التحميل\n${m[1]}'),
  _DynamicRule(RegExp(r'^支払期限 (.+)$'), (m) => 'تاريخ الاستحقاق ${m[1]}'),
  _DynamicRule(RegExp(r'^リマインダー: (.+)$'), (m) => 'تذكير: ${m[1]}'),
  _DynamicRule(RegExp(r'^更新: (.+)$'), (m) => 'حُدّث: ${m[1]}'),
  _DynamicRule(RegExp(r'^登録: (.+)$'), (m) => 'أُنشئ: ${m[1]}'),
  _DynamicRule(RegExp(r'^今日 (.+)$'), (m) => 'اليوم ${m[1]}'),
  _DynamicRule(RegExp(r'^1日 (.+)$'), (m) => 'يومياً ${m[1]}'),
  _DynamicRule(RegExp(r'^貯蓄 (.+)%$'), (m) => 'الادخار ${m[1]}%'),
  _DynamicRule(RegExp(r'^税額合計 (.+)$'), (m) => 'إجمالي الضريبة ${m[1]}'),
  _DynamicRule(RegExp(r'^明細 (.+)$'), (m) => 'العناصر ${m[1]}'),
  _DynamicRule(RegExp(r'^支出 (.+) / 自由枠 (.+)$'),
      (m) => 'المصروف ${m[1]} / المتاح ${m[2]}'),
  _DynamicRule(RegExp(r'^先月より (.+)$'), (m) => 'مقارنة بالشهر الماضي: ${m[1]}'),
  _DynamicRule(RegExp(r'^予算を超えています。残り日数は (\d+) 日です。$'),
      (m) => 'تجاوزت الميزانية. بقي ${m[1]} يوم.'),
  _DynamicRule(RegExp(r'^残り (\d+) 日、1日 (.+) が目安です。$'),
      (m) => 'بقي ${m[1]} يوم؛ نحو ${m[2]} يومياً.'),
  _DynamicRule(
      RegExp(r'^計画より (.+) 多く使っています。残り (\d+) 日、1日 (.+) が目安です。$'),
      (m) =>
          'تنفق ${m[1]} أكثر من الخطة.\nبقي ${m[2]} يوم؛ نحو ${m[3]} يومياً.'),
  _DynamicRule(
      RegExp(r'^計画より (.+) 節約できています。このペースなら貯蓄目標 (.+) に届きます。$'),
      (m) =>
          'توفّر ${m[1]} مقارنة بالخطة.\nبهذه الوتيرة ستصل إلى هدف الادخار ${m[2]}.'),
  _DynamicRule(
      RegExp(r'^計画より (.+) 多く使っています。$'), (m) => 'تنفق ${m[1]} أكثر من الخطة.'),
  _DynamicRule(
      RegExp(r'^計画より (.+) 節約できています。$'), (m) => 'توفّر ${m[1]} مقارنة بالخطة.'),
  _DynamicRule(RegExp(r'^このペースなら貯蓄目標 (.+) に届きます。$'),
      (m) => 'بهذه الوتيرة ستصل إلى هدف الادخار ${m[1]}.'),
  _DynamicRule(RegExp(r'^小計 \+ 消費税 = (.+) と合計 (.+) が一致しません。$'),
      (m) => 'المجموع الفرعي + الضريبة = ${m[1]} لا يطابق الإجمالي ${m[2]}.'),
  _DynamicRule(RegExp(r'^明細合計と合計が一致しません（差額 (.+)）$'),
      (m) => 'إجمالي العناصر لا يطابق إجمالي الإيصال (الفرق ${m[1]}).'),
  _DynamicRule(RegExp(r'^明細合計 (.+) は合計と一致しています$'),
      (m) => 'إجمالي العناصر ${m[1]} يطابق إجمالي الإيصال.'),
];

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return kSupportedAppLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
      AppLocalizations(AppLanguage.fromCode(locale.languageCode)),
    );
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String tr(String source) => l10n.translate(source);
}
