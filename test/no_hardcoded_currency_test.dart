import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files under localization/ are the only place allowed to contain currency
/// symbols and localized currency words.
bool isLocalizationData(String path) =>
    path.replaceAll('\\', '/').contains('lib/core/localization/');

void main() {
  test('no hardcoded yen symbols or yen words outside localization data', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (isLocalizationData(path)) continue;
      final source = entity.readAsStringSync();
      if (source.contains('\u00a5') || source.contains('\u5186')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use the shared currency formatter instead of hardcoding yen '
          'symbols/words in: ${offenders.join(', ')}',
    );
  });

  test('NumberFormat is only used by the shared money formatter', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('core/utils/formatters.dart')) continue;
      if (entity.readAsStringSync().contains('NumberFormat')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join(', '));
  });

  test('legacy yen-only formatters are not used by the UI', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('core/utils/formatters.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('formatYen(') ||
          source.contains('formatCompactYen(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join(', '));
  });
}
