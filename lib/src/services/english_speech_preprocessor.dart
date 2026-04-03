String normalizeEnglishSpeechText(String text) {
  return text
      .replaceAll('\r', '')
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[\u2018\u2019\u201B\u2032\u02BC]'), "'")
      .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
      .replaceAll(RegExp(r'[\u00AD\u200B\u200C\u200D\u2060\uFEFF]'), '');
}

String prepareEnglishSpeechTextForPhonemizer(String text) {
  return normalizeEnglishSpeechText(
    text,
  ).replaceAllMapped(RegExp(r"'s\b"), (match) => "'z");
}
