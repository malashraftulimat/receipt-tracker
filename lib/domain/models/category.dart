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
  '#4CAF50',
  '#FF7043',
  '#42A5F5',
  '#FFB300',
  '#26A69A',
  '#AB47BC',
  '#EF5350',
  '#78909C',
  '#EC407A',
  '#8D6E63',
];

IconData categoryIcon(String key) => kCategoryIcons[key] ?? Icons.category_outlined;

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
        id: '', name: '食費', color: '#4CAF50', icon: 'grocery', isDefault: true, sortOrder: 0),
    ExpenseCategory(
        id: '', name: '外食', color: '#FF7043', icon: 'restaurant', isDefault: true, sortOrder: 1),
    ExpenseCategory(
        id: '', name: '日用品', color: '#42A5F5', icon: 'shopping', isDefault: true, sortOrder: 2),
    ExpenseCategory(
        id: '', name: '光熱費', color: '#FFB300', icon: 'bolt', isDefault: true, sortOrder: 3),
    ExpenseCategory(
        id: '', name: '交通費', color: '#26A69A', icon: 'train', isDefault: true, sortOrder: 4),
    ExpenseCategory(
        id: '', name: '娯楽', color: '#AB47BC', icon: 'games', isDefault: true, sortOrder: 5),
    ExpenseCategory(
        id: '', name: '医療・医薬品', color: '#EF5350', icon: 'pharmacy', isDefault: true, sortOrder: 6),
    ExpenseCategory(
        id: '', name: 'その他', color: '#78909C', icon: 'category', isDefault: true, sortOrder: 7),
  ];
}
