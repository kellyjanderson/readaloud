import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/display_document.dart';
import '../models/reader_document.dart';
import '../models/spoken_selection.dart';
import '../services/display_document_html_renderer.dart';

class DocumentSurface extends StatefulWidget {
  const DocumentSurface({
    super.key,
    required this.document,
    required this.fontFamily,
    required this.fontScale,
    this.focusedDisplayBlockId,
    this.autoFollowActive = false,
    this.onManualScrollWhileFollowing,
    this.scrollController,
    this.spokenSelection = const SpokenSelection.none(),
    this.followRequestTick = 0,
  });

  final ReaderDocument document;
  final String fontFamily;
  final double fontScale;
  final String? focusedDisplayBlockId;
  final bool autoFollowActive;
  final VoidCallback? onManualScrollWhileFollowing;
  final ScrollController? scrollController;
  final SpokenSelection spokenSelection;
  final int followRequestTick;

  @override
  State<DocumentSurface> createState() => _DocumentSurfaceState();
}

class _DocumentSurfaceState extends State<DocumentSurface> {
  late ScrollController _scrollController;
  bool _ownsScrollController = false;

  @override
  void initState() {
    super.initState();
    _bindScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncReadingFocus();
    });
  }

  @override
  void didUpdateWidget(covariant DocumentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      if (_ownsScrollController) {
        _scrollController.dispose();
      }
      _bindScrollController();
    }

    final focusChanged =
        oldWidget.focusedDisplayBlockId != widget.focusedDisplayBlockId ||
        oldWidget.autoFollowActive != widget.autoFollowActive ||
        oldWidget.followRequestTick != widget.followRequestTick ||
        oldWidget.document.displayDocument.documentId !=
            widget.document.displayDocument.documentId;
    if (focusChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncReadingFocus(
          force: oldWidget.followRequestTick != widget.followRequestTick,
        );
      });
    }
  }

  @override
  void dispose() {
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.document.presentation == ReaderDocumentPresentation.pdf &&
        widget.document.pdfData != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: PdfViewer.data(
          widget.document.pdfData!,
          sourceName: widget.document.title,
          params: const PdfViewerParams(),
        ),
      );
    }

    final baseSize = 18.0 * widget.fontScale;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bodyTextColor = theme.colorScheme.onSurface;
    final headingTextColor = isDark
        ? const Color(0xFFF4F7FB)
        : const Color(0xFF16202B);
    final activeBlockColor = isDark
        ? const Color(0x142F3A4A)
        : const Color(0x1AFFBE0B);
    final spokenWordBackground = isDark
        ? const Color(0xFFF4C95D)
        : const Color(0xFFF9D67A);
    final spokenWordTextColor = const Color(0xFF111827);
    final spokenSegmentBackground = isDark
        ? const Color(0x38F4C95D)
        : const Color(0x55FFB703);
    final spokenBlockBackground = isDark
        ? const Color(0x202F3A4A)
        : const Color(0x24FFB703);
    final spokenBlockBorder = isDark
        ? const Color(0xCCF4C95D)
        : const Color(0xD9F59E0B);
    final renderedHtml = renderDisplayDocumentToHtml(
      widget.document.displayDocument,
      spokenSelection: widget.spokenSelection,
    );

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (widget.autoFollowActive &&
            notification.direction != ScrollDirection.idle) {
          widget.onManualScrollWhileFollowing?.call();
        }
        return false;
      },
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          padding: const EdgeInsets.only(right: 8),
          child: SelectionArea(
            child: Html(
              data: renderedHtml,
              shrinkWrap: true,
              extensions: [
                TagExtension(
                  tagsToExtend: const {'audio'},
                  builder: (context) {
                    final src = context.attributes['src'] ?? 'embedded audio';
                    return _EmbeddedContextCard(
                      icon: Icons.audiotrack,
                      title: 'Embedded audio',
                      subtitle: src,
                    );
                  },
                ),
                TagExtension(
                  tagsToExtend: const {'video'},
                  builder: (context) {
                    final src = context.attributes['src'] ?? 'embedded video';
                    return _EmbeddedContextCard(
                      icon: Icons.play_circle_outline,
                      title: 'Embedded video',
                      subtitle: src,
                    );
                  },
                ),
                TagExtension(
                  tagsToExtend: const {'iframe'},
                  builder: (context) {
                    final src = context.attributes['src'] ?? 'embedded frame';
                    return _EmbeddedContextCard(
                      icon: Icons.web_asset_outlined,
                      title: 'Embedded context',
                      subtitle: src,
                    );
                  },
                ),
              ],
              style: {
                'html': Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  backgroundColor: Colors.transparent,
                  fontFamily: widget.fontFamily,
                  color: bodyTextColor,
                ),
                'body': Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  lineHeight: LineHeight.number(1.55),
                  fontSize: FontSize(baseSize),
                  fontFamily: widget.fontFamily,
                  color: bodyTextColor,
                ),
                'article': Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  color: bodyTextColor,
                ),
                'h1': Style(
                  fontSize: FontSize(baseSize * 1.8),
                  fontWeight: FontWeight.w700,
                  margin: Margins.only(bottom: 18, top: 0),
                  color: headingTextColor,
                ),
                'h2': Style(
                  fontSize: FontSize(baseSize * 1.35),
                  fontWeight: FontWeight.w700,
                  margin: Margins.only(top: 22, bottom: 12),
                  color: headingTextColor,
                ),
                'p': Style(
                  margin: Margins.only(bottom: 16),
                  color: bodyTextColor,
                ),
                'blockquote': Style(color: bodyTextColor),
                'li': Style(color: bodyTextColor),
                'code': Style(color: bodyTextColor),
                'pre': Style(color: bodyTextColor),
                'img': Style(
                  width: Width(100, Unit.percent),
                  margin: Margins.symmetric(vertical: 18),
                ),
                '.page-break': Style(
                  border: Border(
                    top: BorderSide(
                      color: const Color(0x22000000),
                      width: 1,
                    ),
                  ),
                  margin: Margins.symmetric(vertical: 18),
                ),
                '.active-reading-block': Style(
                  backgroundColor: activeBlockColor,
                  color: bodyTextColor,
                ),
                '.spoken-word': Style(
                  backgroundColor: spokenWordBackground,
                  fontWeight: FontWeight.w700,
                  color: spokenWordTextColor,
                ),
                '.spoken-segment': Style(
                  backgroundColor: spokenSegmentBackground,
                  fontWeight: FontWeight.w600,
                  color: bodyTextColor,
                ),
                '.spoken-block': Style(
                  backgroundColor: spokenBlockBackground,
                  color: bodyTextColor,
                  border: Border(
                    left: BorderSide(
                      color: spokenBlockBorder,
                      width: 3,
                    ),
                  ),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }

  void _bindScrollController() {
    final providedController = widget.scrollController;
    if (providedController != null) {
      _scrollController = providedController;
      _ownsScrollController = false;
      return;
    }
    _scrollController = ScrollController();
    _ownsScrollController = true;
  }

  void _syncReadingFocus({bool force = false}) {
    if (!mounted ||
        widget.focusedDisplayBlockId == null ||
        !_scrollController.hasClients) {
      return;
    }
    if (!force && !widget.autoFollowActive) {
      return;
    }

    final position = _scrollController.position;
    if (!position.hasViewportDimension) {
      return;
    }

    final targetLeadOffset = _approximateScrollOffsetForBlock(
      widget.document.displayDocument,
      widget.focusedDisplayBlockId!,
      position.maxScrollExtent,
    );
    final viewport = position.viewportDimension;
    final comfortableStart = position.pixels + (viewport * 0.18);
    final comfortableEnd = position.pixels + (viewport * 0.72);
    if (targetLeadOffset >= comfortableStart &&
        targetLeadOffset <= comfortableEnd) {
      return;
    }

    final desiredOffset = (targetLeadOffset - (viewport * 0.22)).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((desiredOffset - position.pixels).abs() < 24) {
      return;
    }

    _scrollController.animateTo(
      desiredOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  double _approximateScrollOffsetForBlock(
    DisplayDocument document,
    String blockId,
    double maxScrollExtent,
  ) {
    if (maxScrollExtent <= 0 || document.blocks.length <= 1) {
      return 0;
    }

    final orderedBlocks = [...document.blocks]
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    final blockIndex = orderedBlocks.indexWhere(
      (block) => block.blockId == blockId,
    );
    if (blockIndex <= 0) {
      return 0;
    }
    if (blockIndex == -1 || blockIndex >= orderedBlocks.length - 1) {
      return maxScrollExtent;
    }
    return maxScrollExtent * (blockIndex / (orderedBlocks.length - 1));
  }
}

class _EmbeddedContextCard extends StatelessWidget {
  const _EmbeddedContextCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1F000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
