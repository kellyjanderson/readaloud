/// Stable IDs used by preferences, factories and UI. Checkpoint revisions and
/// downloaded precision are in assets/fish_drama_models.json.
const speechEngineLabels = <String, String>{
  'kokoro': 'Kokoro',
  'fish_drama3': 'Fish Audio Drama 3 · bf16',
  'fish_drama3_8bit': 'Fish Audio Drama 3 · 8-bit',
  'fish_drama3_4bit': 'Fish Audio Drama 3 · 4-bit',
  'qwen3_tts_base_1_7b': 'Qwen3-TTS 1.7B Base',
  'qwen3_tts_1_7b': 'Qwen3-TTS 1.7B CustomVoice',
  'voxtral_4b': 'Voxtral TTS 4B',
  'moss_tts_8b': 'MOSS-TTS v1.5 8B',
};
bool isDramaEngine(String id) =>
    const {'fish_drama3', 'fish_drama3_8bit', 'fish_drama3_4bit'}.contains(id);
bool isMlxEngine(String? id) =>
    id != 'kokoro' && speechEngineLabels.containsKey(id);
