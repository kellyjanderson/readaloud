import 'package:flutter/material.dart';

import '../models/cast_voice_assignment.dart';
import '../models/character_cast_registry.dart';
import '../models/voice_profile.dart';
import '../services/tts_engine.dart';
import 'voice_library_row.dart';

class VoiceManagementDialog extends StatelessWidget {
  const VoiceManagementDialog({
    super.key,
    required this.voiceLibrary,
    required this.availableVoices,
    required this.characterCastRegistry,
    required this.castVoiceAssignments,
    required this.selectedVoiceId,
    required this.onClose,
    required this.onSelectLibraryVoice,
    required this.onInstallVoice,
    required this.onAssignCastVoice,
  });

  final List<VoiceLibraryEntry> voiceLibrary;
  final List<VoiceProfile> availableVoices;
  final CharacterCastRegistry characterCastRegistry;
  final CastVoiceAssignmentSet? castVoiceAssignments;
  final String? selectedVoiceId;
  final VoidCallback onClose;
  final ValueChanged<String> onSelectLibraryVoice;
  final ValueChanged<String> onInstallVoice;
  final void Function(String castId, String voiceId) onAssignCastVoice;

  @override
  Widget build(BuildContext context) {
    final characterEntries = characterCastRegistry.characterEntries.toList(
      growable: false,
    )..sort((left, right) => left.displayLabel.compareTo(right.displayLabel));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Voice Management',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Manage narrator and character assignments without crowding the primary reading surface.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      'Cast Assignments',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _VoiceAssignmentCard(
                      label: 'Narrator',
                      assignment: castVoiceAssignments?.forCastId(
                        characterCastRegistry.narratorEntry.castId,
                      ),
                      voices: availableVoices,
                      onChanged: (voiceId) => onAssignCastVoice(
                        characterCastRegistry.narratorEntry.castId,
                        voiceId,
                      ),
                    ),
                    if (characterEntries.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Characters',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final entry in characterEntries) ...[
                        _VoiceAssignmentCard(
                          label: entry.displayLabel,
                          assignment: castVoiceAssignments?.forCastId(
                            entry.castId,
                          ),
                          voices: availableVoices,
                          onChanged: (voiceId) =>
                              onAssignCastVoice(entry.castId, voiceId),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    const Divider(height: 32),
                    Text(
                      'Voice Library',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Starter voices are bundled with the app. Optional voices download once and remain installed locally.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    for (var index = 0; index < voiceLibrary.length; index += 1)
                      ...[
                        VoiceLibraryRow(
                          entry: voiceLibrary[index],
                          trailing: _buildLibraryTrailing(
                            context,
                            voiceLibrary[index],
                          ),
                        ),
                        if (index < voiceLibrary.length - 1)
                          const Divider(height: 1),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryTrailing(BuildContext context, VoiceLibraryEntry entry) {
    final isSelected = entry.voice.id == selectedVoiceId;
    final progress = entry.progress;
    final progressPercent = progress == null
        ? null
        : '${(progress * 100).round()}%';

    if (entry.isDownloading) {
      return SizedBox(
        width: 150,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text(progressPercent ?? 'Working...'),
          ],
        ),
      );
    }

    if (entry.isInstalled) {
      return Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (isSelected) const VoiceMetadataPill(label: 'Selected'),
          if (!isSelected)
            FilledButton.tonal(
              onPressed: () => onSelectLibraryVoice(entry.voice.id),
              child: const Text('Use'),
            ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: () => onInstallVoice(entry.voice.id),
      icon: const Icon(Icons.download),
      label: const Text('Download'),
    );
  }
}

class _VoiceAssignmentCard extends StatelessWidget {
  const _VoiceAssignmentCard({
    required this.label,
    required this.assignment,
    required this.voices,
    required this.onChanged,
  });

  final String label;
  final CastVoiceAssignment? assignment;
  final List<VoiceProfile> voices;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedVoice = assignment == null
        ? null
        : voices
              .where((voice) => voice.id == assignment!.effectiveVoiceId)
              .firstOrNull;
    final qualityLabel =
        selectedVoice?.qualityGrade ?? selectedVoice?.targetQuality;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                if (assignment != null)
                  VoiceMetadataPill(
                    label: _decisionLabel(assignment!.decisionKind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: assignment?.effectiveVoiceId,
                    decoration: const InputDecoration(
                      labelText: 'Assigned voice',
                      border: OutlineInputBorder(),
                    ),
                    items: voices
                        .map(
                          (voice) => DropdownMenuItem<String>(
                            value: voice.id,
                            child: Text(
                              voice.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (voiceId) {
                      if (voiceId == null) {
                        return;
                      }
                      onChanged(voiceId);
                    },
                  ),
                ),
                if (qualityLabel != null) ...[
                  const SizedBox(width: 8),
                  VoiceMetadataBadge(label: qualityLabel),
                ],
                if (selectedVoice != null &&
                    (selectedVoice.traits.isNotEmpty ||
                        (selectedVoice.description?.trim().isNotEmpty ??
                            false) ||
                        (selectedVoice.trainingDurationLabel
                                ?.trim()
                                .isNotEmpty ??
                            false))) ...[
                  const SizedBox(width: 4),
                  VoiceMetadataInfoButton(voice: selectedVoice),
                ],
              ],
            ),
            if (selectedVoice != null) ...[
              const SizedBox(height: 8),
              Text(
                selectedVoice.locale,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _decisionLabel(VoiceAssignmentDecisionKind decisionKind) {
    return switch (decisionKind) {
      VoiceAssignmentDecisionKind.automatic => 'Automatic',
      VoiceAssignmentDecisionKind.storedDocumentChoice => 'Stored',
      VoiceAssignmentDecisionKind.userOverride => 'Overridden',
      VoiceAssignmentDecisionKind.fallback => 'Fallback',
    };
  }
}
