import 'package:flutter/material.dart';

import '../models/cast_voice_assignment.dart';
import '../models/character_cast_registry.dart';
import '../models/voice_preview_state.dart';
import '../models/voice_profile.dart';
import '../services/tts_engine.dart';
import '../theme/read_aloud_theme.dart';
import 'voice_library_row.dart';

class VoiceManagementDialog extends StatelessWidget {
  const VoiceManagementDialog({
    super.key,
    required this.isCharacterModeEnabled,
    required this.voiceLibrary,
    required this.availableVoices,
    required this.characterCastRegistry,
    required this.castVoiceAssignments,
    required this.selectedVoiceId,
    required this.previewStateForVoice,
    required this.onClose,
    required this.onSelectLibraryVoice,
    required this.onInstallVoice,
    required this.onToggleVoicePreview,
    required this.onAssignCastVoice,
    required this.onClearCastVoiceOverride,
  });

  final bool isCharacterModeEnabled;
  final List<VoiceLibraryEntry> voiceLibrary;
  final List<VoiceProfile> availableVoices;
  final CharacterCastRegistry characterCastRegistry;
  final CastVoiceAssignmentSet? castVoiceAssignments;
  final String? selectedVoiceId;
  final VoicePreviewState Function(String voiceId) previewStateForVoice;
  final VoidCallback onClose;
  final ValueChanged<String> onSelectLibraryVoice;
  final ValueChanged<String> onInstallVoice;
  final ValueChanged<String> onToggleVoicePreview;
  final void Function(String castId, String voiceId) onAssignCastVoice;
  final ValueChanged<String> onClearCastVoiceOverride;

  @override
  Widget build(BuildContext context) {
    final characterEntries = characterCastRegistry.characterEntries.toList(
      growable: false,
    )..sort((left, right) => left.displayLabel.compareTo(right.displayLabel));
    final tokens = readAloudThemeTokens(context);

    return Dialog(
      backgroundColor: tokens.dialogSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                      previewStateForVoice: previewStateForVoice,
                      onToggleVoicePreview: onToggleVoicePreview,
                      voices: availableVoices,
                      onChanged: (voiceId) => onAssignCastVoice(
                        characterCastRegistry.narratorEntry.castId,
                        voiceId,
                      ),
                      onResetToAutomatic: () => onClearCastVoiceOverride(
                        characterCastRegistry.narratorEntry.castId,
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
                          previewStateForVoice: previewStateForVoice,
                          onToggleVoicePreview: onToggleVoicePreview,
                          voices: availableVoices,
                          onChanged: (voiceId) =>
                              onAssignCastVoice(entry.castId, voiceId),
                          onResetToAutomatic: () =>
                              onClearCastVoiceOverride(entry.castId),
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
                          previewState: previewStateForVoice(
                            voiceLibrary[index].voice.id,
                          ),
                          onTogglePreview: () => onToggleVoicePreview(
                            voiceLibrary[index].voice.id,
                          ),
                          trailing: _buildLibraryTrailing(
                            context,
                            voiceLibrary[index],
                            characterEntries,
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

  Widget _buildLibraryTrailing(
    BuildContext context,
    VoiceLibraryEntry entry,
    List<CastEntry> characterEntries,
  ) {
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
      if (isCharacterModeEnabled && characterEntries.isNotEmpty) {
        return _VoiceLibraryCharacterAssignControl(
          key: Key('voice-library-assign-control-${entry.voice.id}'),
          voiceId: entry.voice.id,
          characterEntries: characterEntries,
          onAssign: (castId) => onAssignCastVoice(castId, entry.voice.id),
        );
      }

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

class _VoiceLibraryCharacterAssignControl extends StatefulWidget {
  const _VoiceLibraryCharacterAssignControl({
    super.key,
    required this.voiceId,
    required this.characterEntries,
    required this.onAssign,
  });

  final String voiceId;
  final List<CastEntry> characterEntries;
  final ValueChanged<String> onAssign;

  @override
  State<_VoiceLibraryCharacterAssignControl> createState() =>
      _VoiceLibraryCharacterAssignControlState();
}

class _VoiceLibraryCharacterAssignControlState
    extends State<_VoiceLibraryCharacterAssignControl> {
  String? _selectedCastId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        key: Key('voice-library-assign-target-${widget.voiceId}'),
        initialValue: _selectedCastId,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Assign',
        ),
        hint: const Text('Assign'),
        items: widget.characterEntries
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry.castId,
                child: Text(
                  entry.displayLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (castId) {
          if (castId == null) {
            return;
          }
          setState(() {
            _selectedCastId = castId;
          });
          widget.onAssign(castId);
        },
      ),
    );
  }
}

class _VoiceAssignmentCard extends StatelessWidget {
  const _VoiceAssignmentCard({
    required this.label,
    required this.assignment,
    required this.previewStateForVoice,
    required this.onToggleVoicePreview,
    required this.voices,
    required this.onChanged,
    required this.onResetToAutomatic,
  });

  final String label;
  final CastVoiceAssignment? assignment;
  final VoicePreviewState Function(String voiceId) previewStateForVoice;
  final ValueChanged<String> onToggleVoicePreview;
  final List<VoiceProfile> voices;
  final ValueChanged<String> onChanged;
  final VoidCallback onResetToAutomatic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = readAloudThemeTokens(context);
    final selectedVoice = assignment == null
        ? null
        : voices
              .where((voice) => voice.id == assignment!.effectiveVoiceId)
              .firstOrNull;
    final automaticVoice = assignment?.automaticVoiceId == null
        ? null
        : voices
              .where((voice) => voice.id == assignment!.automaticVoiceId)
              .firstOrNull;
    final qualityLabel =
        selectedVoice?.qualityGrade ?? selectedVoice?.targetQuality;
    final hasExplicitOverride =
        assignment?.decisionKind == VoiceAssignmentDecisionKind.userOverride;

    return DecoratedBox(
      key: Key('voice-assignment-card-$label'),
      decoration: BoxDecoration(
        color: tokens.elevatedSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.border),
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
            if (automaticVoice != null) ...[
              Text(
                hasExplicitOverride
                    ? 'Automatic voice: ${automaticVoice.displayName}'
                    : 'Using automatic voice selection.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: assignment?.effectiveVoiceId,
                    dropdownColor: tokens.dialogSurface,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    iconEnabledColor: colorScheme.onSurfaceVariant,
                    decoration: InputDecoration(
                      labelText: 'Assigned voice',
                      labelStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                if (selectedVoice?.gender != null) ...[
                  const SizedBox(width: 8),
                  VoiceMetadataPill(
                    label: _genderLabel(selectedVoice!.gender!),
                  ),
                ],
                if (selectedVoice != null) ...[
                  const SizedBox(width: 4),
                  VoicePreviewButton(
                    state: previewStateForVoice(selectedVoice.id),
                    onPressed: () => onToggleVoicePreview(selectedVoice.id),
                  ),
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (selectedVoice.description?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  selectedVoice.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
            if (hasExplicitOverride) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onResetToAutomatic,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Use Automatic Assignment'),
                ),
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

  String _genderLabel(VoiceGender gender) {
    return switch (gender) {
      VoiceGender.female => 'Female',
      VoiceGender.male => 'Male',
      VoiceGender.neutral => 'Neutral',
    };
  }
}
