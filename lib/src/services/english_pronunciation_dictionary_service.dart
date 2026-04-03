import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'english_speech_preprocessor.dart';

class EnglishPronunciationDictionaryService {
  EnglishPronunciationDictionaryService._();

  static final EnglishPronunciationDictionaryService instance =
      EnglishPronunciationDictionaryService._();

  Map<String, String> _entries = const <String, String>{};
  Future<void>? _initializationFuture;

  bool get isInitialized => _entries.isNotEmpty;

  Future<void> initialize() {
    final inFlight = _initializationFuture;
    if (inFlight != null) {
      return inFlight;
    }

    _initializationFuture = _loadAssetDictionary();
    return _initializationFuture!;
  }

  String? lookup(String lexicalTarget) {
    final normalizedTarget = normalizeEnglishSpeechText(
      lexicalTarget,
    ).trim().toLowerCase();
    if (normalizedTarget.isEmpty) {
      return null;
    }
    return _entries[normalizedTarget];
  }

  @visibleForTesting
  void replaceEntriesForTesting(Map<String, String> entries) {
    _entries = Map<String, String>.unmodifiable(
      entries.map(
        (key, value) => MapEntry(
          normalizeEnglishSpeechText(key).trim().toLowerCase(),
          value,
        ),
      ),
    );
    _initializationFuture = Future<void>.value();
  }

  @visibleForTesting
  void resetForTesting() {
    _entries = const <String, String>{};
    _initializationFuture = null;
  }

  Future<void> _loadAssetDictionary() async {
    final rawDictionary = await rootBundle.loadString('assets/cmudict.dict');
    _entries = Map<String, String>.unmodifiable(
      _parseCmudictToIpaEntries(rawDictionary),
    );
  }
}

Map<String, String> _parseCmudictToIpaEntries(String rawDictionary) {
  final entries = <String, String>{};
  for (final rawLine in rawDictionary.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith(';;;')) {
      continue;
    }

    final separatorIndex = line.indexOf(' ');
    if (separatorIndex <= 0) {
      continue;
    }

    final headword = line.substring(0, separatorIndex);
    final pronunciation = line.substring(separatorIndex).trim();
    final normalizedHeadword = _normalizeCmudictHeadword(headword);
    if (normalizedHeadword.isEmpty || entries.containsKey(normalizedHeadword)) {
      continue;
    }

    final ipa = _arpabetToIpa(pronunciation);
    if (ipa.isEmpty) {
      continue;
    }
    entries[normalizedHeadword] = ipa;
  }
  return entries;
}

@visibleForTesting
String convertCmudictArpabetToStandardIpaForTesting(
  String arpabetPronunciation,
) {
  return _arpabetToIpa(arpabetPronunciation);
}

String _normalizeCmudictHeadword(String rawHeadword) {
  return rawHeadword
      .replaceFirst(RegExp(r'\(\d+\)$'), '')
      .trim()
      .toLowerCase();
}

String _arpabetToIpa(String arpabetPronunciation) {
  final buffer = StringBuffer();
  for (final token in arpabetPronunciation.split(RegExp(r'\s+'))) {
    if (token.isEmpty) {
      continue;
    }

    final stressMatch = RegExp(r'^([A-Z]+)([012])?$').firstMatch(token);
    if (stressMatch == null) {
      continue;
    }
    final basePhone = stressMatch.group(1)!;
    final stressDigit = stressMatch.group(2);

    final vowelMapping = _vowelPhoneMap[basePhone];
    if (vowelMapping != null) {
      final stressMarker = switch (stressDigit) {
        '1' => 'ˈ',
        '2' => 'ˌ',
        _ => '',
      };
      final vowel =
          stressDigit == null || stressDigit == '0'
          ? vowelMapping.unstressed
          : vowelMapping.stressed;
      buffer.write('$stressMarker$vowel');
      continue;
    }

    final consonant = _consonantPhoneMap[basePhone];
    if (consonant != null) {
      buffer.write(consonant);
    }
  }
  return buffer.toString();
}

class _VowelPhoneMapping {
  const _VowelPhoneMapping({
    required this.stressed,
    required this.unstressed,
  });

  final String stressed;
  final String unstressed;
}

const Map<String, _VowelPhoneMapping> _vowelPhoneMap =
    <String, _VowelPhoneMapping>{
      'AA': _VowelPhoneMapping(stressed: 'ɑ', unstressed: 'ɑ'),
      'AE': _VowelPhoneMapping(stressed: 'æ', unstressed: 'æ'),
      'AH': _VowelPhoneMapping(stressed: 'ʌ', unstressed: 'ə'),
      'AO': _VowelPhoneMapping(stressed: 'ɔ', unstressed: 'ɔ'),
      'AW': _VowelPhoneMapping(stressed: 'aʊ', unstressed: 'aʊ'),
      'AY': _VowelPhoneMapping(stressed: 'aɪ', unstressed: 'aɪ'),
      'EH': _VowelPhoneMapping(stressed: 'ɛ', unstressed: 'ɛ'),
      'ER': _VowelPhoneMapping(stressed: 'ɝ', unstressed: 'ɚ'),
      'EY': _VowelPhoneMapping(stressed: 'eɪ', unstressed: 'eɪ'),
      'IH': _VowelPhoneMapping(stressed: 'ɪ', unstressed: 'ɪ'),
      'IY': _VowelPhoneMapping(stressed: 'i', unstressed: 'i'),
      'OW': _VowelPhoneMapping(stressed: 'oʊ', unstressed: 'oʊ'),
      'OY': _VowelPhoneMapping(stressed: 'ɔɪ', unstressed: 'ɔɪ'),
      'UH': _VowelPhoneMapping(stressed: 'ʊ', unstressed: 'ʊ'),
      'UW': _VowelPhoneMapping(stressed: 'u', unstressed: 'u'),
      'AX': _VowelPhoneMapping(stressed: 'ə', unstressed: 'ə'),
      'AXR': _VowelPhoneMapping(stressed: 'ɚ', unstressed: 'ɚ'),
      'IX': _VowelPhoneMapping(stressed: 'ɨ', unstressed: 'ɨ'),
    };

const Map<String, String> _consonantPhoneMap = <String, String>{
  'B': 'b',
  'CH': 'tʃ',
  'D': 'd',
  'DH': 'ð',
  'DX': 'ɾ',
  'EL': 'l',
  'EM': 'm',
  'EN': 'n',
  'F': 'f',
  'G': 'ɡ',
  'HH': 'h',
  'JH': 'dʒ',
  'K': 'k',
  'L': 'l',
  'M': 'm',
  'N': 'n',
  'NG': 'ŋ',
  'NX': 'ɾ̃',
  'P': 'p',
  'Q': 'ʔ',
  'R': 'ɹ',
  'S': 's',
  'SH': 'ʃ',
  'T': 't',
  'TH': 'θ',
  'V': 'v',
  'W': 'w',
  'WH': 'ʍ',
  'Y': 'j',
  'Z': 'z',
  'ZH': 'ʒ',
};
