const List<(String, String)> _kokoroIpaReplacementTable = <(String, String)>[
  // Standard IPA affricates to Kokoro's single-character inventory.
  ('dʒ', 'ʤ'),
  ('tʃ', 'ʧ'),

  // Standard American stressed rhotic vowel to Kokoro-compatible sequence.
  ('ɝ', 'ɜɹ'),
];

String adaptStandardIpaToKokoroPhonemes(String phonemeString) {
  var adapted = phonemeString;
  for (final (source, replacement) in _kokoroIpaReplacementTable) {
    adapted = adapted.replaceAll(source, replacement);
  }
  return adapted;
}
