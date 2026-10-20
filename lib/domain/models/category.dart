import 'package:flutter/material.dart';

/// Icon keys are stored as short strings so the DB stays UI-agnostic.
const Map<String, IconData> kCategoryIcons = <String, IconData>{
  'grocery': Icons.local_grocery_store_outlined,
  'restaurant': Icons.restaurant_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'bolt': Icons.bolt_outlined,
  'train': Icons.directions_transit_outlined,
  'games': Icons.sports_esports_outlined,
  'pharmacy': Icons.local_pharmacy_outlined,
  'cafe': Icons.local_cafe_outlined,
  'home': Icons.home_outlined,
  'category': Icons.category_outlined,
};

const List<String> kCategoryIconKeys = <String>[
  'grocery',
  'restaurant',
  'shopping',
  'bolt',
  'train',
  'games',
  'pharmacy',
  'cafe',
  'home',
  'category',
];

const List<String> kCategoryColors = <String>[
  '#FF8FA3',
  '#FFA36C',
  '#A78BFA',
  '#FFD166',
  '#74B9FF',
  '#C084FC',
  '#55EFC4',
  '#9AA8C7',
  '#00CEC9',
  '#FF6B81',
];

IconData categoryIcon(String key) =>
    kCategoryIcons[key] ?? Icons.category_outlined;

/// Expense category (custom or seeded default).
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;

  /// Hex string, e.g. `#4CAF50`.
  final String color;
  final String icon;
  final bool isDefault;
  final int sortOrder;

  Color get colorValue {
    final hex = color.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16) ?? 0x78909C;
    return Color(0xFF000000 | value);
  }

  IconData get iconData => categoryIcon(icon);

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未分類',
      color: json['color'] as String? ?? '#78909C',
      icon: json['icon'] as String? ?? 'category',
      isDefault: json['is_default'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'color': color,
        'icon': icon,
        'is_default': isDefault,
        'sort_order': sortOrder,
      };

  Map<String, dynamic> toRow() => <String, dynamic>{
        'name': name,
        'color': color,
        'icon': icon,
        'is_default': isDefault,
        'sort_order': sortOrder,
      };

  ExpenseCategory copyWith({
    String? name,
    String? color,
    String? icon,
    int? sortOrder,
  }) {
    return ExpenseCategory(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      isDefault: isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Seeded into `users/{userId}/categories` on first sign-in.
  static const List<ExpenseCategory> templates = <ExpenseCategory>[
    ExpenseCategory(
        id: '',
        name: '食費',
        color: '#FF8FA3',
        icon: 'grocery',
        isDefault: true,
        sortOrder: 0),
    ExpenseCategory(
        id: '',
        name: '外食',
        color: '#FFA36C',
        icon: 'restaurant',
        isDefault: true,
        sortOrder: 1),
    ExpenseCategory(
        id: '',
        name: '日用品',
        color: '#A78BFA',
        icon: 'shopping',
        isDefault: true,
        sortOrder: 2),
    ExpenseCategory(
        id: '',
        name: '光熱費',
        color: '#FFD166',
        icon: 'bolt',
        isDefault: true,
        sortOrder: 3),
    ExpenseCategory(
        id: '',
        name: '交通費',
        color: '#74B9FF',
        icon: 'train',
        isDefault: true,
        sortOrder: 4),
    ExpenseCategory(
        id: '',
        name: '娯楽',
        color: '#C084FC',
        icon: 'games',
        isDefault: true,
        sortOrder: 5),
    ExpenseCategory(
        id: '',
        name: '医療・医薬品',
        color: '#55EFC4',
        icon: 'pharmacy',
        isDefault: true,
        sortOrder: 6),
    ExpenseCategory(
        id: '',
        name: 'その他',
        color: '#9AA8C7',
        icon: 'category',
        isDefault: true,
        sortOrder: 7),
  ];
}
