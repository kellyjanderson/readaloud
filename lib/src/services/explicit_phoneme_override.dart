class ExplicitPhonemeSuffixOverride {
  const ExplicitPhonemeSuffixOverride({
    required this.originalToken,
    required this.leadingPunctuation,
    required this.baseSurfaceText,
    required this.normalizedBaseSurfaceText,
    required this.suffixPhoneme,
    required this.trailingPunctuation,
  });

  final String originalToken;
  final String leadingPunctuation;
  final String baseSurfaceText;
  final String normalizedBaseSurfaceText;
  final String suffixPhoneme;
  final String trailingPunctuation;
}

ExplicitPhonemeSuffixOverride? parseExplicitPhonemeSuffixOverride(
  String token,
) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final leadingPunctuation =
      RegExp(r'^[^A-Za-z0-9]+').firstMatch(trimmed)?.group(0) ?? '';
  final trailingPunctuation =
      RegExp(r'[^A-Za-z0-9|]+$').firstMatch(trimmed)?.group(0) ?? '';
  final coreStart = leadingPunctuation.length;
  final coreEnd = trimmed.length - trailingPunctuation.length;
  if (coreStart >= coreEnd) {
    return null;
  }

  final core = trimmed.substring(coreStart, coreEnd);
  final match = RegExp(r"^([A-Za-z][A-Za-z'’-]*?)\|([^|]+)\|$").firstMatch(
    core,
  );
  if (match == null) {
    return null;
  }

  final baseWithOptionalMarkerApostrophe = match.group(1)!.replaceAll('’', "'");
  final baseSurfaceText = baseWithOptionalMarkerApostrophe.endsWith("'")
      ? baseWithOptionalMarkerApostrophe.substring(
          0,
          baseWithOptionalMarkerApostrophe.length - 1,
        )
      : baseWithOptionalMarkerApostrophe;
  final normalizedBaseSurfaceText = baseSurfaceText
      .replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '')
      .trim()
      .toLowerCase();
  if (normalizedBaseSurfaceText.isEmpty) {
    return null;
  }

  final suffixPhoneme = _normalizeExplicitSuffixPhoneme(match.group(2)!);
  if (suffixPhoneme == null) {
    return null;
  }

  return ExplicitPhonemeSuffixOverride(
    originalToken: trimmed,
    leadingPunctuation: leadingPunctuation,
    baseSurfaceText: baseSurfaceText,
    normalizedBaseSurfaceText: normalizedBaseSurfaceText,
    suffixPhoneme: suffixPhoneme,
    trailingPunctuation: trailingPunctuation,
  );
}

String? _normalizeExplicitSuffixPhoneme(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final lowered = trimmed.toLowerCase();
  switch (lowered) {
    case 'z':
    case '-z':
      return 'z';
    case 's':
    case '-s':
      return 's';
    case 'es':
    case '-es':
    case 'iz':
    case '-iz':
    case 'əz':
    case '-əz':
    case 'ɪz':
    case '-ɪz':
      return 'ɪz';
  }

  return trimmed.startsWith('-') ? trimmed.substring(1) : trimmed;
}
