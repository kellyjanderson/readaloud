import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/mlx_voice_library.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/voice_preview_state.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/widgets/voice_management_dialog.dart';

void main() {
  testWidgets('English library dialog exposes all 43 selectable references', (
    tester,
  ) async {
    await MlxVoiceLibrary.load();
    final voices = MlxVoiceLibrary.profiles;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceManagementDialog(
            engineName: 'Qwen Base',
            isCharacterModeEnabled: false,
            availableVoices: voices,
            voiceLibrary: voices
                .map(
                  (v) => VoiceLibraryEntry(
                    voice: v,
                    isInstalled: true,
                    isBundled: true,
                  ),
                )
                .toList(),
            characterCastRegistry:
                ReaderDocument.sample().characterCastRegistry,
            castVoiceAssignments: null,
            selectedVoiceId: voices.first.id,
            previewStateForVoice: (_) => VoicePreviewState.idle,
            onClose: () {},
            onSelectLibraryVoice: (_) {},
            onInstallVoice: (_) {},
            onToggleVoicePreview: (_) {},
            onAssignCastVoice: (_, _) {},
            onClearCastVoiceOverride: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Qwen Base · 43 English voice choices'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(dropdown.items!.length, 43);
    expect(dropdown.items!.map((item) => item.value).toSet().length, 43);
    expect(tester.takeException(), isNull);
  });
}
