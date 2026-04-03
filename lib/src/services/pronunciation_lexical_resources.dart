import '../models/pronunciation_artifact.dart';

// App-owned pronunciation resources should prefer standard IPA.
// Engine-specific adaptation belongs at the TTS boundary.
const Map<String, List<PronunciationRepresentation>>
globalEnglishPronunciationLexicalResources =
    <String, List<PronunciationRepresentation>>{
      'api': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_api_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'eɪpiːˈaɪ',
          accentFamily: null,
          priority: 100,
        ),
      ],
      'dart': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_dart_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'dˈɑɹt',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'elliot': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_elliot_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'ˈɛliət',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'electrocyte': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_electrocyte_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'ɪlˈɛktɹəsaɪt',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'electrocytes': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_electrocytes_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'ɪlˈɛktɹəsaɪts',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'epub': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_epub_spoken',
          representationType: 'normalized_spoken_text',
          representationValue: 'E pub',
          accentFamily: null,
          priority: 70,
        ),
      ],
      'exclaimed': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_exclaimed_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'ɪksklˈeɪmd',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'for': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_for_spoken',
          representationType: 'normalized_spoken_text',
          representationValue: 'four',
          accentFamily: null,
          priority: 100,
        ),
      ],
      'flutter': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_flutter_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'flˈʌtɚ',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'html': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_html_spoken',
          representationType: 'normalized_spoken_text',
          representationValue: 'H T M L',
          accentFamily: null,
          priority: 70,
        ),
      ],
      'json': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_json_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'dʒeɪsˈɑn',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'john': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_john_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'dʒˈɑn',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'kokoro': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_kokoro_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'koʊ koʊ ɹoʊ',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'pdf': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_pdf_spoken',
          representationType: 'normalized_spoken_text',
          representationValue: 'P D F',
          accentFamily: null,
          priority: 70,
        ),
      ],
    };

const Map<String, List<PronunciationRepresentation>>
enUsCorePronunciationLexicalResources =
    <String, List<PronunciationRepresentation>>{
      'retorted': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_retorted_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'ɹɪtˈɔɹtɪd',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
      'stomped': <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'lex_stomped_phoneme',
          representationType: 'phoneme_string',
          representationValue: 'stˈɑmpt',
          accentFamily: 'en-us',
          priority: 100,
        ),
      ],
    };

const Map<String, List<PronunciationRepresentation>>
enGbCorePronunciationLexicalResources =
    <String, List<PronunciationRepresentation>>{};

const Map<String, List<PronunciationRepresentation>>
enAuCorePronunciationLexicalResources =
    <String, List<PronunciationRepresentation>>{};

const Map<String, List<PronunciationRepresentation>>
enUsGermanAccentedPronunciationLexicalResources =
    <String, List<PronunciationRepresentation>>{};

const Map<String, Map<String, List<PronunciationRepresentation>>>
defaultPronunciationResourceLayers =
    <String, Map<String, List<PronunciationRepresentation>>>{
      'global-en': globalEnglishPronunciationLexicalResources,
      'en-us-core': enUsCorePronunciationLexicalResources,
      'en-gb-core': enGbCorePronunciationLexicalResources,
      'en-au-core': enAuCorePronunciationLexicalResources,
      'en-us-german-accented':
          enUsGermanAccentedPronunciationLexicalResources,
    };

const Map<String, List<PronunciationRepresentation>>
defaultDocumentTimePronunciationLexicalResources =
    globalEnglishPronunciationLexicalResources;
