import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/reader_controller.dart';
import '../models/reader_document.dart';
import '../widgets/document_surface.dart';
import '../widgets/reading_focus_recenter_button.dart';
import '../widgets/voice_management_dialog.dart';

enum _AppMenuAction {
  open,
  paste,
  sample,
  saveAudio,
  readerOptions,
  liveFeed,
}

class ReadAloudScreen extends StatefulWidget {
  const ReadAloudScreen({
    super.key,
    this.initialInputPaths = const <String>[],
  });

  final List<String> initialInputPaths;

  @override
  State<ReadAloudScreen> createState() => _ReadAloudScreenState();
}

class _ReadAloudScreenState extends State<ReadAloudScreen> {
  late final ReaderController _controller;
  late final ScrollController _ttsTraceScrollController;
  bool _isDraggingFiles = false;

  @override
  void initState() {
    super.initState();
    _controller = ReaderController();
    _ttsTraceScrollController = ScrollController();
    unawaited(_initializeController());
  }

  @override
  void dispose() {
    _ttsTraceScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final status = _controller.statusMessage;
        final isBuffering = _controller.isBufferingPlayback;
        final transportEnabled =
            _controller.document.wordCount > 0 && !isBuffering;
        final reader = _buildReader(context);

        return Title(
          title: _controller.windowTitle,
          color: Theme.of(context).colorScheme.primary,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: const Text('Read Aloud'),
              actions: [
                PopupMenuButton<_AppMenuAction>(
                  tooltip: 'Reader menu',
                  onSelected: _handleAppMenuAction,
                  itemBuilder: (context) => <PopupMenuEntry<_AppMenuAction>>[
                    const PopupMenuItem<_AppMenuAction>(
                      value: _AppMenuAction.open,
                      child: Text('Open Document'),
                    ),
                    const PopupMenuItem<_AppMenuAction>(
                      value: _AppMenuAction.paste,
                      child: Text('Paste Text'),
                    ),
                    const PopupMenuItem<_AppMenuAction>(
                      value: _AppMenuAction.sample,
                      child: Text('Load Sample'),
                    ),
                    PopupMenuItem<_AppMenuAction>(
                      value: _AppMenuAction.saveAudio,
                      enabled:
                          !_controller.isExporting && _controller.canExportAudio,
                      child: Text(
                        _controller.isExporting
                            ? 'Saving Audio...'
                            : 'Save Audio',
                      ),
                    ),
                    PopupMenuItem<_AppMenuAction>(
                      value: _AppMenuAction.liveFeed,
                      child: Text(
                        _controller.isLiveReadEnabled
                            ? 'Stop Live Feed'
                            : 'Live Feed',
                      ),
                    ),
                    const PopupMenuItem<_AppMenuAction>(
                      value: _AppMenuAction.readerOptions,
                      child: Text('Reader Options'),
                    ),
                  ],
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bodyContent = reader;
                final intakeSurface = DropTarget(
                  onDragEntered: (_) => setState(() => _isDraggingFiles = true),
                  onDragExited: (_) => setState(() => _isDraggingFiles = false),
                  onDragDone: (detail) {
                    setState(() => _isDraggingFiles = false);
                    _controller.importDroppedFiles(detail.files);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(child: bodyContent),
                      if (_isDraggingFiles)
                        const Positioned.fill(child: _DropOverlay()),
                    ],
                  ),
                );

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      children: [
                        if (_controller.isInitializing)
                          const LinearProgressIndicator(minHeight: 2),
                        if (status != null) ...[
                          const SizedBox(height: 12),
                          Material(
                            color: const Color(0xFFFFF4D6),
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              leading: const Icon(Icons.info_outline),
                              title: Text(status),
                              trailing: IconButton(
                                onPressed: _controller.clearStatus,
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Expanded(child: intakeSurface),
                      ],
                    ),
                  );
                },
              ),
            ),
            bottomNavigationBar: Material(
              color: const Color(0xFFF7F5EF),
              elevation: 12,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildPrimaryVoiceSelector(context),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${_controller.currentWordIndex} / ${_controller.document.wordCount} words',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: transportEnabled
                                ? () => _controller.jumpBySeconds(-30)
                                : null,
                            icon: const Icon(Icons.replay_30),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: isBuffering
                                  ? FilledButton.styleFrom(
                                      disabledBackgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      disabledForegroundColor: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    )
                                  : null,
                              onPressed: transportEnabled
                                  ? _controller.togglePlayback
                                  : null,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: isBuffering
                                    ? const _LoadingDots(
                                        key: ValueKey('buffering'),
                                      )
                                    : Icon(
                                        _controller.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        key: ValueKey(_controller.isPlaying),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: transportEnabled
                                ? () => _controller.jumpBySeconds(30)
                                : null,
                            icon: const Icon(Icons.forward_30),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    if (widget.initialInputPaths.isNotEmpty) {
      await _controller.importFilePaths(widget.initialInputPaths);
      return;
    }
    await _controller.restoreLastOpenedDocument();
  }

  Future<void> _saveAudio() async {
    try {
      final pickedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Audio',
        fileName: _controller.suggestedAudioExportFileName,
        type: FileType.custom,
        allowedExtensions: const <String>['wav'],
      );
      if (pickedPath == null || pickedPath.trim().isEmpty) {
        return;
      }
      final outputPath = pickedPath.toLowerCase().endsWith('.wav')
          ? pickedPath
          : '$pickedPath.wav';
      await _controller.exportAudioToPath(outputPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start Save Audio: $error')),
      );
    }
  }

  Future<void> _handleAppMenuAction(_AppMenuAction action) async {
    switch (action) {
      case _AppMenuAction.open:
        if (_controller.isImporting) {
          return;
        }
        await _controller.importDocument();
      case _AppMenuAction.paste:
        await _showPasteDialog();
      case _AppMenuAction.sample:
        await _controller.loadSampleDocument();
      case _AppMenuAction.saveAudio:
        if (_controller.isExporting || !_controller.canExportAudio) {
          return;
        }
        await _saveAudio();
      case _AppMenuAction.readerOptions:
        await _showReaderOptionsSheet();
      case _AppMenuAction.liveFeed:
        if (_controller.isLiveReadEnabled) {
          await _controller.stopLiveRead();
          return;
        }
        await _controller.pickAndStartLiveRead();
    }
  }

  Future<void> _showReaderOptionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = math.min(
          MediaQuery.of(context).size.height * 0.88,
          720.0,
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(height: maxHeight, child: _buildControls(context)),
          ),
        );
      },
    );
  }

  Widget _buildPrimaryVoiceSelector(BuildContext context) {
    final selectedVoiceId = _controller.selectedVoice?.id;
    final voices = _controller.voices;
    final canManageVoices = _controller.canManageVoices;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x16000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedVoiceId,
                  hint: const Text('Select voice'),
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
                  onChanged: voices.isEmpty ? null : _controller.selectVoiceById,
                ),
              ),
            ),
            if (canManageVoices) ...[
              const SizedBox(width: 4),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              IconButton(
                tooltip: 'Voice options',
                onPressed: _showVoiceManagerDialog,
                icon: const Icon(Icons.tune),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final remaining = _controller.sleepTimerRemaining;
    final speedLabel = '${_controller.currentSpeed.toStringAsFixed(2)}x';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            blurRadius: 24,
            color: Color(0x16000000),
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Reader Controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_controller.selectedVoice?.id ?? 'no-voice'),
            initialValue: _controller.selectedVoice?.id,
            decoration: const InputDecoration(
              labelText: 'Voice',
              border: OutlineInputBorder(),
            ),
            items: _controller.voices
                .map(
                  (voice) => DropdownMenuItem<String>(
                    value: voice.id,
                    child: Text(
                      voice.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _controller.voices.isEmpty
                ? null
                : _controller.selectVoiceById,
          ),
          if (_controller.canManageVoices) ...[
            const SizedBox(height: 8),
            Text(
              'Use the integrated voice options control on the primary bar to manage narrator and cast voices.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          _LabeledSlider(
            label: 'Voice Speed',
            valueLabel: speedLabel,
            value: _controller.currentSpeed,
            min: 0.7,
            max: 1.4,
            onChanged: _controller.voices.isEmpty
                ? null
                : _controller.setVoiceSpeed,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_controller.fontFamily),
            initialValue: _controller.fontFamily,
            decoration: const InputDecoration(
              labelText: 'Reading Font',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'serif', child: Text('Serif')),
              DropdownMenuItem(value: 'sans-serif', child: Text('Sans Serif')),
              DropdownMenuItem(value: 'monospace', child: Text('Monospace')),
            ],
            onChanged: (value) {
              if (value == null) return;
              _controller.setFontFamily(value);
            },
          ),
          const SizedBox(height: 16),
          _LabeledSlider(
            label: 'Font Scale',
            valueLabel: '${_controller.fontScale.toStringAsFixed(2)}x',
            value: _controller.fontScale,
            min: 0.9,
            max: 1.6,
            onChanged: _controller.setFontScale,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Duration?>(
            key: ValueKey(_controller.sleepTimerDuration?.inSeconds ?? 0),
            initialValue: _controller.sleepTimerDuration,
            decoration: const InputDecoration(
              labelText: 'Sleep Timer',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem<Duration?>(value: null, child: Text('Off')),
              DropdownMenuItem<Duration?>(
                value: Duration(minutes: 15),
                child: Text('15 minutes'),
              ),
              DropdownMenuItem<Duration?>(
                value: Duration(minutes: 30),
                child: Text('30 minutes'),
              ),
              DropdownMenuItem<Duration?>(
                value: Duration(minutes: 45),
                child: Text('45 minutes'),
              ),
              DropdownMenuItem<Duration?>(
                value: Duration(minutes: 60),
                child: Text('60 minutes'),
              ),
            ],
            onChanged: _controller.setSleepTimer,
          ),
          if (remaining != null) ...[
            const SizedBox(height: 8),
            Text(
              _controller.isFadingOut
                  ? 'Sleep timer is fading playback out.'
                  : 'Sleep timer remaining: ${_formatDuration(remaining)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Divider(height: 32),
          Text('Timing Model', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Current estimate: ${_controller.wordsPerSecond.toStringAsFixed(2)} words/sec',
          ),
          Text(
            'Jump buttons use the observed timing from the current reading session.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          Text('Live Read', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _controller.isLiveReadEnabled
                ? 'Watching a file for changes and reloading only the current document inside the running app.'
                : 'Attach a file to create a live text feed into the running app. When the file changes, Read Aloud reloads the document in place.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_controller.liveReadFilePath != null) ...[
            SelectableText(
              _controller.liveReadFilePath!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _controller.pickAndStartLiveRead,
                icon: const Icon(Icons.sync),
                label: Text(
                  _controller.isLiveReadEnabled
                      ? 'Change Live File'
                      : 'Choose Live File',
                ),
              ),
              if (_controller.isLiveReadEnabled)
                TextButton.icon(
                  onPressed: () => _controller.stopLiveRead(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Live Mode'),
                ),
            ],
          ),
          const Divider(height: 32),
          Text(
            'TTS Input Trace',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Live tail of the exact text, payload units, and phoneme strings being sent into the current TTS session.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_controller.ttsDebugTraceLogPath != null) ...[
            Text(
              'Voice: ${_controller.ttsDebugTraceVoiceId ?? 'unknown'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_controller.ttsDebugTraceStartedAt != null)
              Text(
                'Started: ${_controller.ttsDebugTraceStartedAt!.toLocal().toIso8601String()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            SelectableText(
              _controller.ttsDebugTraceLogPath!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ] else ...[
            Text(
              'No TTS trace has been captured yet. Start playback to create a session log.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 220,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Scrollbar(
                  controller: _ttsTraceScrollController,
                  child: SingleChildScrollView(
                    controller: _ttsTraceScrollController,
                    reverse: true,
                    child: SelectionArea(
                      child: SelectableText(
                        _controller.ttsDebugTraceLines.isEmpty
                            ? 'Waiting for a TTS trace...'
                            : _controller.ttsDebugTraceLines.join('\n'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: const Color(0xFFF9FAFB),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          Text(
            'Document Source',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_controller.document.sourceDescription ?? 'No source metadata'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _controller.document.attachments
                .map(
                  (attachment) => Chip(
                    avatar: Icon(_iconForAttachment(attachment.type), size: 18),
                    label: Text(attachment.label),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            blurRadius: 28,
            color: Color(0x18000000),
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: DocumentSurface(
                document: _controller.document,
                fontFamily: _controller.fontFamily,
                fontScale: _controller.fontScale,
                spokenSelection: _controller.spokenSelection,
                focusedDisplayBlockId:
                    _controller.readingFocusState.activeDisplayBlockId,
                autoFollowActive:
                    _controller.readingFocusState.shouldAutoFollow,
                followRequestTick:
                    _controller.readingFocusState.recenterRequestTick,
                onManualScrollWhileFollowing:
                    _controller.suspendReaderFollow,
              ),
            ),
            if (_controller.readingFocusState.canRecenter)
              Positioned(
                right: 12,
                bottom: 12,
                child: ReadingFocusRecenterButton(
                  onPressed: _controller.resumeReaderFollow,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasteDialog() async {
    final controller = TextEditingController();
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Paste Text'),
          content: SizedBox(
            width: 640,
            child: TextField(
              controller: controller,
              maxLines: 16,
              decoration: const InputDecoration(
                hintText: 'Paste a document, article, or chapter here…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _controller.importPastedText(controller.text);
              },
              child: Text(
                'Load',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showVoiceManagerDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return VoiceManagementDialog(
              voiceLibrary: _controller.voiceLibrary,
              availableVoices: _controller.voices,
              characterCastRegistry: _controller.document.characterCastRegistry,
              castVoiceAssignments: _controller.castVoiceAssignments,
              selectedVoiceId: _controller.selectedVoice?.id,
              onClose: Navigator.of(context).pop,
              onSelectLibraryVoice: (voiceId) {
                unawaited(_controller.selectVoiceById(voiceId));
              },
              onInstallVoice: (voiceId) {
                unawaited(_controller.installVoice(voiceId));
              },
              onAssignCastVoice: (castId, voiceId) {
                unawaited(_controller.assignVoiceToCast(castId, voiceId));
              },
              onClearCastVoiceOverride: (castId) {
                unawaited(_controller.clearCastVoiceOverride(castId));
              },
            );
          },
        );
      },
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCCFFF7E0),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFCA6702), width: 3),
        ),
        margin: const EdgeInsets.all(6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.file_download_outlined, size: 44),
                const SizedBox(height: 12),
                Text(
                  'Drop Files To Import',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Read Aloud will open the first supported document and keep the same reading pipeline as picker and share intake.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots({super.key});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = (_controller.value * 3).floor() % 3;
        final dots = List<String>.generate(3, (index) {
          return index <= phase ? '•' : '·';
        }).join(' ');
        return Text(
          dots,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

IconData _iconForAttachment(ReaderAttachmentType type) {
  switch (type) {
    case ReaderAttachmentType.image:
      return Icons.image_outlined;
    case ReaderAttachmentType.audio:
      return Icons.graphic_eq;
    case ReaderAttachmentType.video:
      return Icons.movie_outlined;
    case ReaderAttachmentType.other:
      return Icons.attach_file;
  }
}
