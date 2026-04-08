import 'package:flutter/material.dart';

import '../models/voice_preview_state.dart';
import '../models/voice_profile.dart';
import '../services/tts_engine.dart';
import '../theme/read_aloud_theme.dart';

class VoiceLibraryRow extends StatelessWidget {
  const VoiceLibraryRow({
    super.key,
    required this.entry,
    this.previewState = VoicePreviewState.idle,
    this.onTogglePreview,
    this.trailing,
  });

  final VoiceLibraryEntry entry;
  final VoicePreviewState previewState;
  final VoidCallback? onTogglePreview;
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
    final summaryText = _summaryTextForEntry(entry);
    final isPlaceholderSummary = summaryText == _noDescriptionSummary;

    return ListTile(
      tileColor: readAloudThemeTokens(context).elevatedSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
          const SizedBox(width: 12),
          _MetadataSlot(
            width: 60,
            child: qualityLabel == null
                ? null
                : VoiceMetadataBadge(label: qualityLabel),
          ),
          const SizedBox(width: 8),
          _MetadataSlot(
            width: 96,
            child: voice.gender == null
                ? null
                : VoiceMetadataPill(label: _genderLabel(voice.gender!)),
          ),
          const SizedBox(width: 4),
          _MetadataSlot(
            width: 40,
            child: VoicePreviewButton(
              state: previewState,
              onPressed: onTogglePreview,
            ),
          ),
          const SizedBox(width: 4),
          _MetadataSlot(
            width: 40,
            child: hasMetadataDetails
                ? VoiceMetadataInfoButton(voice: voice)
                : null,
          ),
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
          const SizedBox(height: 8),
          _VoiceRowSummaryLine(
            text: summaryText,
            isPlaceholder: isPlaceholderSummary,
          ),
        ],
      ),
      trailing: trailing,
    );
  }

  static const String _noDescriptionSummary = 'No description available';

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

  static String _genderLabel(VoiceGender gender) {
    return switch (gender) {
      VoiceGender.female => 'Female',
      VoiceGender.male => 'Male',
      VoiceGender.neutral => 'Neutral',
    };
  }

  static String _summaryTextForEntry(VoiceLibraryEntry entry) {
    final description = entry.voice.description?.trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }

    final statusMessage = entry.statusMessage?.trim();
    if (statusMessage != null && statusMessage.isNotEmpty) {
      return statusMessage;
    }

    return _noDescriptionSummary;
  }
}

class _MetadataSlot extends StatelessWidget {
  const _MetadataSlot({required this.width, this.child});

  final double width;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerLeft,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class _VoiceRowSummaryLine extends StatelessWidget {
  const _VoiceRowSummaryLine({
    required this.text,
    required this.isPlaceholder,
  });

  final String text;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return SizedBox(
      height: 20,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isPlaceholder
              ? textStyle?.copyWith(fontStyle: FontStyle.italic)
              : textStyle,
        ),
      ),
    );
  }
}

class VoicePreviewButton extends StatelessWidget {
  const VoicePreviewButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  final VoicePreviewState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      VoicePreviewState.idle => Icons.play_arrow_rounded,
      VoicePreviewState.loading => Icons.hourglass_top_rounded,
      VoicePreviewState.playing => Icons.stop_rounded,
    };
    final tooltip = switch (state) {
      VoicePreviewState.idle => 'Preview voice',
      VoicePreviewState.loading => 'Voice preview is loading',
      VoicePreviewState.playing => 'Stop voice preview',
    };

    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
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
        final tokens = readAloudThemeTokens(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.elevatedSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: tokens.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
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
    final tokens = readAloudThemeTokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.qualityBadgeBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: tokens.qualityBadgeForeground,
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
    final tokens = readAloudThemeTokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.metadataPillBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tokens.metadataPillForeground,
          ),
        ),
      ),
    );
  }
}
