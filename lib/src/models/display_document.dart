enum DisplayBlockKind {
  heading,
  paragraph,
  orderedList,
  unorderedList,
  listItem,
  blockquote,
  codeBlock,
  image,
  audio,
  video,
  table,
  pageBreak,
  separator,
  unsupported,
}

enum DisplayInlineKind {
  text,
  emphasis,
  strong,
  link,
  inlineCode,
  lineBreak,
  superscript,
  subscript,
}

enum DisplayAssetKind { image, audio, video, attachment }

class DisplayDocument {
  const DisplayDocument({
    required this.documentId,
    required this.sourceType,
    required this.sourceUri,
    required this.title,
    required this.blocks,
    required this.assets,
    required this.metadata,
    required this.normalizationVersion,
  });

  final String documentId;
  final String sourceType;
  final Uri? sourceUri;
  final String title;
  final List<DisplayBlock> blocks;
  final Map<String, DisplayAsset> assets;
  final Map<String, String> metadata;
  final String normalizationVersion;
}

class DisplayBlock {
  const DisplayBlock({
    required this.blockId,
    required this.kind,
    required this.inlines,
    required this.attributes,
    required this.assetId,
    required this.parentBlockId,
    required this.ordinal,
  });

  final String blockId;
  final DisplayBlockKind kind;
  final List<DisplayInline> inlines;
  final Map<String, String> attributes;
  final String? assetId;
  final String? parentBlockId;
  final int ordinal;

  String get plainText => inlines.map((inline) => inline.text).join();
}

class DisplayInline {
  const DisplayInline({
    required this.kind,
    required this.text,
    required this.attributes,
  });

  final DisplayInlineKind kind;
  final String text;
  final Map<String, String> attributes;
}

class DisplayAsset {
  const DisplayAsset({
    required this.assetId,
    required this.kind,
    required this.resolvedUri,
    required this.mimeType,
    required this.metadata,
  });

  final String assetId;
  final DisplayAssetKind kind;
  final Uri resolvedUri;
  final String? mimeType;
  final Map<String, String> metadata;
}
