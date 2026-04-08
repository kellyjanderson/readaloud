import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/reader_controller.dart';
import '../models/reader_appearance_mode.dart';
import '../models/reader_document.dart';
import '../theme/read_aloud_theme.dart';
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
    this.controller,
  });

  final List<String> initialInputPaths;
  final ReaderController? controller;

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
    _controller = widget.controller ?? ReaderController();
    _ttsTraceScrollController = ScrollController();
    unawaited(_initializeController());
  }

  @override
  void dispose() {
    _ttsTraceScrollController.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final usesDesktopNativeMenus = _usesDesktopNativeMenus();
        final tokens = readAloudThemeTokens(context);
        final isBuffering = _controller.isBufferingPlayback;
        final transportEnabled =
            _controller.document.wordCount > 0 && !isBuffering;
        final reader = _buildReader(context);

        final scaffold = Scaffold(
          appBar: usesDesktopNativeMenus
              ? null
              : AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  title: const Text('Read Aloud'),
                  actions: [
                    PopupMenuButton<_AppMenuAction>(
                      key: const Key('reader-overflow-menu'),
                      tooltip: 'Reader menu',
                      onSelected: _handleAppMenuAction,
                      itemBuilder: _buildMobileOverflowMenuEntries,
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
                      const SizedBox(height: 12),
                      Expanded(child: intakeSurface),
                    ],
                  ),
                );
              },
            ),
          ),
          bottomNavigationBar: Material(
            color: tokens.chromeSurface,
            elevation: 12,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPrimaryVoiceSelector(context),
                    const SizedBox(height: 8),
                    _SegmentedTransportCapsule(
                      isBuffering: isBuffering,
                      isPlaying: _controller.isPlaying,
                      enabled: transportEnabled,
                      onJumpBack: transportEnabled
                          ? () => _controller.jumpBySeconds(-30)
                          : null,
                      onTogglePlayback: transportEnabled
                          ? _controller.togglePlayback
                          : null,
                      onJumpForward: transportEnabled
                          ? () => _controller.jumpBySeconds(30)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final shell = usesDesktopNativeMenus
            ? PlatformMenuBar(menus: _buildDesktopMenus(), child: scaffold)
            : scaffold;

        return Title(
          title: _controller.windowTitle,
          color: Theme.of(context).colorScheme.primary,
          child: shell,
        );
      },
    );
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    if (!mounted) {
      return;
    }
    if (widget.initialInputPaths.isNotEmpty) {
      await _controller.importFilePaths(widget.initialInputPaths);
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    await _controller.restoreLastOpenedDocument();
  }

  bool _usesDesktopNativeMenus() {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  }

  List<PopupMenuEntry<_AppMenuAction>> _buildMobileOverflowMenuEntries(
    BuildContext context,
  ) {
    return <PopupMenuEntry<_AppMenuAction>>[
      const _OverflowMenuSectionLabel(label: 'Document'),
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
      const PopupMenuDivider(),
      const _OverflowMenuSectionLabel(label: 'Output'),
      PopupMenuItem<_AppMenuAction>(
        value: _AppMenuAction.saveAudio,
        enabled: !_controller.isExporting && _controller.canExportAudio,
        child: Text(_controller.isExporting ? 'Saving Audio...' : 'Save Audio'),
      ),
      const PopupMenuDivider(),
      const _OverflowMenuSectionLabel(label: 'Live Input'),
      PopupMenuItem<_AppMenuAction>(
        value: _AppMenuAction.liveFeed,
        child: Text(
          _controller.isLiveReadEnabled ? 'Stop Live Feed' : 'Live Feed',
        ),
      ),
      const PopupMenuDivider(),
      const _OverflowMenuSectionLabel(label: 'Settings'),
      const PopupMenuItem<_AppMenuAction>(
        value: _AppMenuAction.readerOptions,
        child: Text('Reader Options'),
      ),
    ];
  }

  List<PlatformMenuItem> _buildDesktopMenus() {
    return <PlatformMenuItem>[
      PlatformMenu(
        label: 'Read Aloud',
        menus: _buildDesktopApplicationMenuItems(),
      ),
      PlatformMenu(label: 'File', menus: _buildDesktopFileMenuItems()),
    ];
  }

  List<PlatformMenuItem> _buildDesktopApplicationMenuItems() {
    final items = <PlatformMenuItem>[
      if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.about))
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.about,
        ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Reader Options...',
            shortcut: SingleActivator(LogicalKeyboardKey.comma, meta: true),
            onSelected: () {
              unawaited(_handleAppMenuAction(_AppMenuAction.readerOptions));
            },
          ),
        ],
      ),
    ];

    if (PlatformProvidedMenuItem.hasMenu(
      PlatformProvidedMenuItemType.servicesSubmenu,
    )) {
      items.add(
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.servicesSubmenu,
        ),
      );
    }

    final windowItems = <PlatformMenuItem>[
      if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.hide))
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
      if (PlatformProvidedMenuItem.hasMenu(
        PlatformProvidedMenuItemType.hideOtherApplications,
      ))
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.hideOtherApplications,
        ),
      if (PlatformProvidedMenuItem.hasMenu(
        PlatformProvidedMenuItemType.showAllApplications,
      ))
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.showAllApplications,
        ),
      if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.quit))
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
    ];
    if (windowItems.isNotEmpty) {
      items.add(PlatformMenuItemGroup(members: windowItems));
    }
    return items;
  }

  List<PlatformMenuItem> _buildDesktopFileMenuItems() {
    return <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Open Document...',
            shortcut: SingleActivator(LogicalKeyboardKey.keyO, meta: true),
            onSelected: () {
              unawaited(_handleAppMenuAction(_AppMenuAction.open));
            },
          ),
          PlatformMenuItem(
            label: 'Paste Text...',
            onSelected: () {
              unawaited(_handleAppMenuAction(_AppMenuAction.paste));
            },
          ),
          PlatformMenuItem(
            label: 'Load Sample',
            onSelected: () {
              unawaited(_handleAppMenuAction(_AppMenuAction.sample));
            },
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: _controller.isExporting
                ? 'Saving Audio...'
                : 'Save Audio...',
            shortcut: SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            ),
            onSelected: !_controller.isExporting && _controller.canExportAudio
                ? () {
                    unawaited(_handleAppMenuAction(_AppMenuAction.saveAudio));
                  }
                : null,
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: _controller.isLiveReadEnabled
                ? 'Stop Live Feed'
                : 'Live Feed...',
            onSelected: () {
              unawaited(_handleAppMenuAction(_AppMenuAction.liveFeed));
            },
          ),
        ],
      ),
    ];
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
      _controller.showStatusMessage(_saveAudioDialogFailureMessage(error));
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
    if (_controller.isMultiVoiceEnabled) {
      return _buildCastEntrypoint(context);
    }

    final tokens = readAloudThemeTokens(context);
    final selectedVoiceId = _controller.selectedVoice?.id;
    final voices = _controller.voices;
    final canManageVoices = _controller.canManageVoices;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.elevatedSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
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
                  onChanged: voices.isEmpty
                      ? null
                      : _controller.selectVoiceById,
                ),
              ),
            ),
            if (canManageVoices) ...[
              const SizedBox(width: 4),
              VerticalDivider(width: 1, thickness: 1, color: tokens.border),
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

  Widget _buildCastEntrypoint(BuildContext context) {
    final tokens = readAloudThemeTokens(context);
    final canOpen = _controller.voices.isNotEmpty;

    return Material(
      color: tokens.elevatedSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('character-voices-entry'),
        onTap: canOpen ? _showVoiceManagerDialog : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Character Voices',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = readAloudThemeTokens(context);
    final remaining = _controller.sleepTimerRemaining;
    final speedLabel = '${_controller.currentSpeed.toStringAsFixed(2)}x';
    final voiceSelectorLabel = _controller.isMultiVoiceEnabled
        ? 'Narrator Voice'
        : 'Voice';

    return DecoratedBox(
      key: const Key('reader-options-sheet'),
      decoration: BoxDecoration(
        color: tokens.dialogSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            blurRadius: 24,
            color: tokens.surfaceShadow,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(20),
        children: [
          Text('Reader Options', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Secondary reading preferences, timing controls, diagnostics, and source details live here so the main Reader surface can stay calm.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _ReaderOptionsSectionCard(
            title: 'Voices and Reading',
            description:
                'Control narrator behavior, appearance, and how the document feels while you read.',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(_controller.selectedVoice?.id ?? 'no-voice'),
                  initialValue: _controller.selectedVoice?.id,
                  decoration: InputDecoration(labelText: voiceSelectorLabel),
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
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  key: const Key('multi-voice-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Multi-Voice Reading'),
                  subtitle: Text(
                    _controller.isMultiVoiceEnabled
                        ? 'Narration stays with the narrator voice while quoted dialogue routes through the cast.'
                        : 'Use one narrator voice for the whole document.',
                  ),
                  value: _controller.isMultiVoiceEnabled,
                  onChanged: _controller.voices.isEmpty
                      ? null
                      : (enabled) {
                          unawaited(_controller.setMultiVoiceEnabled(enabled));
                        },
                ),
                if (_controller.canManageVoices) ...[
                  const SizedBox(height: 8),
                  Text(
                    _controller.isMultiVoiceEnabled
                        ? 'Use the integrated character voices control on the primary bar, or manage narrator and cast voices here.'
                        : 'Use the integrated voice options control on the primary bar to manage available voices.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_controller.isMultiVoiceEnabled) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _controller.voices.isEmpty
                          ? null
                          : _showVoiceManagerDialog,
                      icon: const Icon(Icons.record_voice_over_outlined),
                      label: const Text('Set Character Voices'),
                    ),
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
                  decoration: const InputDecoration(labelText: 'Reading Font'),
                  items: const [
                    DropdownMenuItem(value: 'serif', child: Text('Serif')),
                    DropdownMenuItem(
                      value: 'sans-serif',
                      child: Text('Sans Serif'),
                    ),
                    DropdownMenuItem(
                      value: 'monospace',
                      child: Text('Monospace'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _controller.setFontFamily(value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ReaderAppearanceMode>(
                  key: ValueKey(_controller.appearanceMode),
                  initialValue: _controller.appearanceMode,
                  decoration: const InputDecoration(labelText: 'Appearance'),
                  items: ReaderAppearanceMode.values
                      .map(
                        (mode) => DropdownMenuItem<ReaderAppearanceMode>(
                          value: mode,
                          child: Text(mode.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    unawaited(_controller.setAppearanceMode(value));
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ReaderOptionsSectionCard(
            title: 'Sleep and Timing',
            description:
                'Set playback wind-down behavior and inspect the timing model behind jumping and follow-along.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<Duration?>(
                  key: ValueKey(_controller.sleepTimerDuration?.inSeconds ?? 0),
                  initialValue: _controller.sleepTimerDuration,
                  decoration: const InputDecoration(labelText: 'Sleep Timer'),
                  items: const [
                    DropdownMenuItem<Duration?>(
                      value: null,
                      child: Text('Off'),
                    ),
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
                  const SizedBox(height: 10),
                  Text(
                    _controller.isFadingOut
                        ? 'Sleep timer is fading playback out.'
                        : 'Sleep timer remaining: ${_formatDuration(remaining)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Current estimate: ${_controller.wordsPerSecond.toStringAsFixed(2)} words/sec',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Jump buttons use the observed timing from the current reading session.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ReaderOptionsSectionCard(
            title: 'Diagnostics',
            description:
                'Inspect the live TTS input trace and current session metadata without turning the main reader into a debug surface.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_controller.ttsDebugTraceLogPath != null) ...[
                  Text(
                    'Voice: ${_controller.ttsDebugTraceVoiceId ?? 'unknown'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_controller.ttsDebugTraceStartedAt != null)
                    Text(
                      'Started: ${_controller.ttsDebugTraceStartedAt!.toLocal().toIso8601String()}',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _controller.ttsDebugTraceLogPath!,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text(
                    'No TTS trace has been captured yet. Start playback to create a session log.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.technicalSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: tokens.border),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: kTechnicalFontFamily,
                                color: tokens.technicalOnSurface,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ReaderOptionsSectionCard(
            title: 'Document Source',
            description:
                'Review the current source metadata and related attachments for the open document.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _controller.document.sourceDescription ??
                      'No source metadata',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _controller.document.attachments
                      .map(
                        (attachment) => Chip(
                          avatar: Icon(
                            _iconForAttachment(attachment.type),
                            size: 18,
                          ),
                          label: Text(attachment.label),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(BuildContext context) {
    final tokens = readAloudThemeTokens(context);
    return DecoratedBox(
      key: const Key('reader-surface-shell'),
      decoration: BoxDecoration(
        color: tokens.readerSurface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: tokens.readerBorder),
        boxShadow: [
          BoxShadow(
            blurRadius: 28,
            color: tokens.surfaceShadow,
            offset: const Offset(0, 14),
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
                onManualScrollWhileFollowing: _controller.suspendReaderFollow,
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
            if (_controller.isCastProcessingVisible)
              Positioned.fill(
                child: _CastProcessingOverlay(
                  stageLabel: _controller.documentLoadStageLabel,
                  progress: _controller.documentLoadStageProgress,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasteDialog() async {
    final controller = TextEditingController();

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
              child: Text('Load'),
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
              isCharacterModeEnabled: _controller.isMultiVoiceEnabled,
              voiceLibrary: _controller.voiceLibrary,
              availableVoices: _controller.voices,
              characterCastRegistry: _controller.document.characterCastRegistry,
              castVoiceAssignments: _controller.castVoiceAssignments,
              selectedVoiceId: _controller.selectedVoice?.id,
              previewStateForVoice: _controller.previewStateForVoice,
              onClose: Navigator.of(context).pop,
              onSelectLibraryVoice: (voiceId) {
                unawaited(_controller.selectVoiceById(voiceId));
              },
              onInstallVoice: (voiceId) {
                unawaited(_controller.installVoice(voiceId));
              },
              onToggleVoicePreview: (voiceId) {
                unawaited(_controller.toggleVoicePreview(voiceId));
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
    final tokens = readAloudThemeTokens(context);
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: tokens.dropOverlaySurface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: tokens.dropOverlayBorder, width: 2.5),
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

class _CastProcessingOverlay extends StatelessWidget {
  const _CastProcessingOverlay({
    required this.stageLabel,
    required this.progress,
  });

  final String stageLabel;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = readAloudThemeTokens(context);
    return IgnorePointer(
      child: Container(
        key: const Key('cast-processing-overlay'),
        decoration: BoxDecoration(
          color: tokens.processingScrim,
          borderRadius: BorderRadius.circular(24),
        ),
        margin: const EdgeInsets.all(8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.processingSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: tokens.processingBorder),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 24,
                    color: tokens.surfaceShadow,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_motion_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Preparing Multi-Voice Reading',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(stageLabel, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 14),
                    Text(
                      'We are scanning dialogue, consolidating characters, and materializing narrator-versus-cast routing before playback starts.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
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

class _ReaderOptionsSectionCard extends StatelessWidget {
  const _ReaderOptionsSectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = readAloudThemeTokens(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.elevatedSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SegmentedTransportCapsule extends StatelessWidget {
  const _SegmentedTransportCapsule({
    required this.isBuffering,
    required this.isPlaying,
    required this.enabled,
    required this.onJumpBack,
    required this.onTogglePlayback,
    required this.onJumpForward,
  });

  final bool isBuffering;
  final bool isPlaying;
  final bool enabled;
  final VoidCallback? onJumpBack;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onJumpForward;

  @override
  Widget build(BuildContext context) {
    final tokens = readAloudThemeTokens(context);
    return Material(
      key: const Key('transport-capsule'),
      color: tokens.elevatedSurface,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tokens.border),
        ),
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _TransportSegment(
                  key: const Key('transport-back'),
                  icon: Icons.replay_30,
                  onPressed: onJumpBack,
                  enabled: enabled,
                  alignment: Alignment.centerLeft,
                ),
              ),
              _TransportDivider(color: tokens.border),
              Expanded(
                flex: 5,
                child: _TransportSegment(
                  key: const Key('transport-center'),
                  icon: isPlaying ? Icons.pause : Icons.play_arrow,
                  onPressed: onTogglePlayback,
                  enabled: enabled,
                  alignment: Alignment.center,
                  isPrimary: true,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: isBuffering
                        ? const _LoadingDots(key: ValueKey('buffering'))
                        : Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            key: ValueKey<bool>(isPlaying),
                          ),
                  ),
                ),
              ),
              _TransportDivider(color: tokens.border),
              Expanded(
                flex: 3,
                child: _TransportSegment(
                  key: const Key('transport-forward'),
                  icon: Icons.forward_30,
                  onPressed: onJumpForward,
                  enabled: enabled,
                  alignment: Alignment.centerRight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportSegment extends StatelessWidget {
  const _TransportSegment({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.enabled,
    required this.alignment,
    this.isPrimary = false,
    this.child,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final Alignment alignment;
  final bool isPrimary;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = enabled
        ? (isPrimary ? colorScheme.primary : colorScheme.onSurface)
        : colorScheme.onSurface.withValues(alpha: 0.38);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: alignment,
          child: IconTheme(
            data: IconThemeData(size: isPrimary ? 28 : 24, color: foreground),
            child:
                child ??
                Icon(icon, semanticLabel: isPrimary ? 'Play or pause' : null),
          ),
        ),
      ),
    );
  }
}

class _TransportDivider extends StatelessWidget {
  const _TransportDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: color.withValues(alpha: 0.6),
    );
  }
}

class _OverflowMenuSectionLabel extends PopupMenuEntry<_AppMenuAction> {
  const _OverflowMenuSectionLabel({required this.label});

  final String label;

  @override
  double get height => 30;

  @override
  bool represents(_AppMenuAction? value) => false;

  @override
  State<_OverflowMenuSectionLabel> createState() =>
      _OverflowMenuSectionLabelState();
}

class _OverflowMenuSectionLabelState extends State<_OverflowMenuSectionLabel> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
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
          ).textTheme.titleMedium?.copyWith(color: IconTheme.of(context).color),
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

String _saveAudioDialogFailureMessage(Object error) {
  final normalized = error.toString().toLowerCase();
  if (normalized.contains('not implemented') ||
      normalized.contains('missingpluginexception') ||
      normalized.contains('unavailable')) {
    return 'Save Audio is not available right now.';
  }
  return 'Could not open Save Audio right now. Try choosing the destination again.';
}
