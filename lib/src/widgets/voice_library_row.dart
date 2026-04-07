import 'package:flutter/material.dart';

import '../models/voice_profile.dart';
import '../services/tts_engine.dart';

class VoiceLibraryRow extends StatelessWidget {
  const VoiceLibraryRow({
    super.key,
    required this.entry,
    this.trailing,
  });

  final VoiceLibraryEntry entry;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final voice = entry.voice;
    final installStateLabel = _installStateLabel(entry);
    final qualityLabel = voice.qualityGrade ?? voice.targetQuality;
    final hasMetadataDetails =
        voice.traits.isNotEmpty ||
        (voice.description?.trim().isNotEmpty ?? false) ||
        (voice.trainingDurationLabel?.trim().isNotEmpty ?? false);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              voice.label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (qualityLabel != null) ...[
            const SizedBox(width: 8),
            VoiceMetadataBadge(label: qualityLabel),
          ],
          if (hasMetadataDetails) ...[
            const SizedBox(width: 4),
            VoiceMetadataInfoButton(voice: voice),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (voice.locale.isNotEmpty)
                Text(
                  voice.locale,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              VoiceMetadataPill(label: installStateLabel),
              if (entry.isBundled) const VoiceMetadataPill(label: 'Included'),
            ],
          ),
          if (entry.statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              entry.statusMessage!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      trailing: trailing,
    );
  }

  static String _installStateLabel(VoiceLibraryEntry entry) {
    if (entry.isDownloading) {
      final progress = entry.progress;
      if (progress == null) {
        return 'Downloading';
      }
      return 'Downloading ${(progress * 100).round()}%';
    }
    if (entry.isInstalled) {
      return 'Installed';
    }
    return 'Available';
  }
}

class VoiceMetadataInfoButton extends StatelessWidget {
  const VoiceMetadataInfoButton({super.key, required this.voice});

  final VoiceProfile voice;

  @override
  Widget build(BuildContext context) {
    final summary = _metadataSummary(voice);
    return Tooltip(
      message: summary,
      waitDuration: const Duration(milliseconds: 250),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Voice details',
        onPressed: () => _showMetadataSheet(context, voice),
        icon: const Icon(Icons.info_outline),
      ),
    );
  }

  String _metadataSummary(VoiceProfile voice) {
    final parts = <String>[
      if (voice.traits.isNotEmpty) voice.traits.join(', '),
      if (voice.trainingDurationLabel != null)
        'Training: ${voice.trainingDurationLabel}',
      if (voice.description != null) voice.description!,
    ];
    return parts.join('\n');
  }

  void _showMetadataSheet(BuildContext context, VoiceProfile voice) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voice.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (voice.locale.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    voice.locale,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (voice.traits.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: voice.traits
                        .map((trait) => VoiceMetadataPill(label: trait))
                        .toList(growable: false),
                  ),
                ],
                if (voice.trainingDurationLabel != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Training: ${voice.trainingDurationLabel}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (voice.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    voice.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class VoiceMetadataBadge extends StatelessWidget {
  const VoiceMetadataBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class VoiceMetadataPill extends StatelessWidget {
  const VoiceMetadataPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
