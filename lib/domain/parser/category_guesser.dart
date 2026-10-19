/// Very small keyword classifier used to pre-select a category for a receipt
/// and for each line item. Matches the default Japanese category names.
class CategoryGuesser {
  const CategoryGuesser._();

  static const String fallback = 'その他';

  /// Most specific categories first (外食 before 食費, etc.).
  static const List<MapEntry<String, List<String>>> rules =
      <MapEntry<String, List<String>>>[
    MapEntry<String, List<String>>('外食', <String>[
      'サイゼリヤ',
      'マクドナルド',
      'モスバーガー',
      'ケンタッキー',
      'スターバックス',
      'ドトール',
      'タリーズ',
      'コメダ',
      '吉野家',
      'すき家',
      '松屋',
      '餃子',
      'ラーメン',
      '寿司',
      '居酒屋',
      'レストラン',
      'カフェ',
      'ランチ',
      'ディナー',
      '定食',
      '弁当',
      'テイクアウト',
      '食券',
      'ドリンク',
      'コーヒー',
    ]),
    MapEntry<String, List<String>>('食費', <String>[
      '牛乳',
      'パン',
      '卵',
      '米',
      '野菜',
      '果物',
      '精肉',
      '鮮魚',
      '豆腐',
      '納豆',
      'ヨーグルト',
      'おにぎり',
      'サンドイッチ',
      '菓子',
      'スナック',
      '飲料',
      'お茶',
      'ミネラルウォーター',
      '冷凍',
      '惣菜',
      'スーパー',
      'イオン',
      'セブン',
      'ローソン',
      'ファミリーマート',
      'ライフ',
      '西友',
      'マルエツ',
      '業務スーパー',
    ]),
    MapEntry<String, List<String>>('日用品', <String>[
      '洗剤',
      '柔軟剤',
      'ティッシュ',
      'トイレットペーパー',
      'キッチンペーパー',
      'シャンプー',
      'コンディショナー',
      '歯ブラシ',
      '歯磨き',
      'ボディソープ',
      'ゴミ袋',
      'ラップ',
      'スポンジ',
      '掃除',
      '洗濯',
      'マスク',
      'ドラッグ',
      '薬局',
      'ダイソー',
      'セリア',
    ]),
    MapEntry<String, List<String>>('光熱費', <String>[
      '電気',
      '電力',
      'ガス',
      '水道',
      '上下水道',
      'nhk',
      '通信',
      'インターネット',
      '携帯',
      'docomo',
      'softbank',
      'au',
      '楽天モバイル',
    ]),
    MapEntry<String, List<String>>('交通費', <String>[
      '電車',
      'バス',
      'タクシー',
      'suica',
      'pasmo',
      'jr',
      '私鉄',
      'ガソリン',
      '給油',
      '駐車',
      'パーキング',
      '新幹線',
      '航空',
    ]),
    MapEntry<String, List<String>>('娯楽', <String>[
      'ゲーム',
      '映画',
      'シネマ',
      '書籍',
      'コミック',
      'dvd',
      'blu-ray',
      'サブスク',
      'spotify',
      'netflix',
      'steam',
      'プレイステーション',
      'ニンテンドー',
      'ゲームセンター',
      'カラオケ',
    ]),
    MapEntry<String, List<String>>('医療・医薬品', <String>[
      '処方',
      '調剤',
      '診察',
      '診療',
      '病院',
      'クリニック',
      '歯科',
      '薬',
      '医療',
    ]),
  ];

  /// Returns the most likely default category name, or null when unsure.
  static String? guess(String text) {
    final haystack = text.toLowerCase();
    for (final rule in rules) {
      for (final keyword in rule.value) {
        if (haystack.contains(keyword.toLowerCase())) return rule.key;
      }
    }
    return null;
  }

  /// Counts keyword hits so a receipt can be tagged from its items.
  static String? guessFromMany(Iterable<String> texts) {
    final scores = <String, int>{};
    for (final text in texts) {
      final haystack = text.toLowerCase();
      for (final rule in rules) {
        for (final keyword in rule.value) {
          if (haystack.contains(keyword.toLowerCase())) {
            scores[rule.key] = (scores[rule.key] ?? 0) + 1;
            break;
          }
        }
      }
    }
    if (scores.isEmpty) return null;
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.value >= 1 ? sorted.first.key : null;
  }
}
