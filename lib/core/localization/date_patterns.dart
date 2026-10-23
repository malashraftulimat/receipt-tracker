/// Intl date patterns per language.
///
/// Patterns live with the localization data because Japanese / Arabic calendar
/// notation contains script characters that must not appear in UI code.
const Map<String, Map<String, String>> kDatePatterns =
    <String, Map<String, String>>{
  'full': <String, String>{
    'ja': 'yyyy年M月d日(E)',
    'en': 'EEE, MMM d, y',
    'ar': 'EEEE، d MMMM y',
  },
  'short': <String, String>{
    'ja': 'yyyy/M/d(E)',
    'en': 'M/d/yy (EEE)',
    'ar': 'd/M/y (EEE)',
  },
  'month': <String, String>{
    'ja': 'yyyy年M月',
    'en': 'MMMM y',
    'ar': 'MMMM y',
  },
  'day': <String, String>{
    'ja': 'M月d日(E)',
    'en': 'EEE, MMM d',
    'ar': 'EEEE، d MMMM',
  },
  'year': <String, String>{
    'ja': 'yyyy年',
    'en': 'y',
    'ar': 'y',
  },
  'month_short': <String, String>{
    'ja': 'M月',
    'en': 'MMM',
    'ar': 'MMM',
  },
  'weekday_full': <String, String>{
    'ja': 'EEEE',
    'en': 'EEEE',
    'ar': 'EEEE',
  },
  'weekday_short': <String, String>{
    'ja': 'E',
    'en': 'E',
    'ar': 'E',
  },
  'range_separator': <String, String>{
    'ja': ' 〜 ',
    'en': ' – ',
    'ar': ' – ',
  },
};
