import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../models/reader_document.dart';

class DocumentSurface extends StatefulWidget {
  const DocumentSurface({
    super.key,
    required this.document,
    required this.fontFamily,
    required this.fontScale,
  });

  final ReaderDocument document;
  final String fontFamily;
  final double fontScale;

  @override
  State<DocumentSurface> createState() => _DocumentSurfaceState();
}

class _DocumentSurfaceState extends State<DocumentSurface> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = 18.0 * widget.fontScale;

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        primary: false,
        padding: const EdgeInsets.only(right: 8),
        child: Html(
          data: widget.document.displayHtml,
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
            ),
            'body': Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              lineHeight: LineHeight.number(1.55),
              fontSize: FontSize(baseSize),
              fontFamily: widget.fontFamily,
            ),
            'article': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
            'h1': Style(
              fontSize: FontSize(baseSize * 1.8),
              fontWeight: FontWeight.w700,
              margin: Margins.only(bottom: 18, top: 0),
            ),
            'h2': Style(
              fontSize: FontSize(baseSize * 1.35),
              fontWeight: FontWeight.w700,
              margin: Margins.only(top: 22, bottom: 12),
            ),
            'p': Style(margin: Margins.only(bottom: 16)),
            'img': Style(
              width: Width(100, Unit.percent),
              margin: Margins.symmetric(vertical: 18),
            ),
          },
        ),
      ),
    );
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
