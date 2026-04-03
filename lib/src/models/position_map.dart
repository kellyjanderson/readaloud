class PositionMap {
  const PositionMap({
    required this.documentId,
    required this.mappingVersion,
    required this.entries,
  });

  final String documentId;
  final String mappingVersion;
  final List<PositionMapEntry> entries;
}

class PositionMapEntry {
  const PositionMapEntry({
    required this.entryId,
    required this.displayBlockId,
    required this.speechSegmentId,
    required this.displayStart,
    required this.displayEnd,
    required this.speechStartWord,
    required this.speechEndWord,
    required this.confidence,
    this.recoveryAnchor,
    this.sourceAnchor,
  });

  final String entryId;
  final String displayBlockId;
  final String speechSegmentId;
  final int displayStart;
  final int displayEnd;
  final int speechStartWord;
  final int speechEndWord;
  final double confidence;
  final RecoveryAnchor? recoveryAnchor;
  final SourceAnchor? sourceAnchor;
}

class RecoveryAnchor {
  const RecoveryAnchor({
    required this.exact,
    this.prefix,
    this.suffix,
  });

  final String exact;
  final String? prefix;
  final String? suffix;
}

sealed class SourceAnchor {
  const SourceAnchor();
}

class EpubSourceAnchor extends SourceAnchor {
  const EpubSourceAnchor({this.spineItemId, this.cfi});

  final String? spineItemId;
  final String? cfi;
}

class PdfSourceAnchor extends SourceAnchor {
  const PdfSourceAnchor({required this.pageIndex, this.sourceBlockId});

  final int pageIndex;
  final String? sourceBlockId;
}

class HtmlSourceAnchor extends SourceAnchor {
  const HtmlSourceAnchor({this.cssSelector});

  final String? cssSelector;
}
