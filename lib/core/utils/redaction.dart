/// Removes credentials from diagnostic text before it is logged or shown.
///
/// Gemini uses the `x-goog-api-key` header, so the key normally never appears
/// in a URL. This is defence in depth for error objects that include headers,
/// query strings or request dumps.
final List<RegExp> _redactionPatterns = <RegExp>[
  // Query parameters: ?key=..., &api_key=...
  RegExp(
    r'([?&](?:key|api_key|apikey)=)[^&\s#"<>]+',
    caseSensitive: false,
  ),
  // Headers.
  RegExp(
    r'(x-goog-api-key\s*[:=]\s*)[^\s,;"<>]+',
    caseSensitive: false,
  ),
  RegExp(
    r'(authorization\s*:\s*bearer\s+)[^\s,;"<>]+',
    caseSensitive: false,
  ),
  // JSON / Dart map style fields.
  RegExp(
    r'("?(?:apiKey|api_key|authorizationKey)"?\s*[:=]\s*"?)[^"\\\s,;<>]+',
    caseSensitive: false,
  ),
];

final List<RegExp> _tokenPatterns = <RegExp>[
  RegExp(r'\bAIza[0-9A-Za-z_\-]{20,}\b'),
  RegExp(r'\bAQ\.[0-9A-Za-z_\-]{10,}\b'),
  RegExp(r'\bBearer\s+[A-Za-z0-9._\-]{20,}\b'),
];

/// Returns [text] with API keys / bearer tokens replaced by `[REDACTED]`.
///
/// A known [apiKey] can be supplied as well, so the exact value is scrubbed
/// even if it appears in an unexpected format.
String redactSensitiveText(String text, {String? apiKey}) {
  var result = text;

  final knownKey = apiKey?.trim();
  if (knownKey != null && knownKey.isNotEmpty) {
    result = result.replaceAll(knownKey, '[REDACTED]');
  }

  for (final pattern in _redactionPatterns) {
    result = result.replaceAllMapped(
      pattern,
      (match) => '${match.group(1) ?? ''}[REDACTED]',
    );
  }
  for (final pattern in _tokenPatterns) {
    result = result.replaceAll(pattern, '[REDACTED]');
  }
  return result;
}
