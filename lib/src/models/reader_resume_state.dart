class ReaderResumeState {
  const ReaderResumeState({
    required this.documentPath,
    required this.wordIndex,
    required this.wordIndexWithinSegment,
    this.segmentTextAnchor,
    this.anchorWordText,
  });

  final String documentPath;
  final int wordIndex;
  final int wordIndexWithinSegment;
  final String? segmentTextAnchor;
  final String? anchorWordText;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentPath': documentPath,
      'wordIndex': wordIndex,
      'wordIndexWithinSegment': wordIndexWithinSegment,
      'segmentTextAnchor': segmentTextAnchor,
      'anchorWordText': anchorWordText,
    };
  }

  static ReaderResumeState? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final documentPath = value['documentPath'];
    final wordIndex = value['wordIndex'];
    final wordIndexWithinSegment = value['wordIndexWithinSegment'];
    if (documentPath is! String ||
        documentPath.trim().isEmpty ||
        wordIndex is! num ||
        wordIndexWithinSegment is! num) {
      return null;
    }

    final segmentTextAnchor = value['segmentTextAnchor'];
    final anchorWordText = value['anchorWordText'];
    return ReaderResumeState(
      documentPath: documentPath,
      wordIndex: wordIndex.toInt(),
      wordIndexWithinSegment: wordIndexWithinSegment.toInt(),
      segmentTextAnchor: segmentTextAnchor is String && segmentTextAnchor.isNotEmpty
          ? segmentTextAnchor
          : null,
      anchorWordText: anchorWordText is String && anchorWordText.isNotEmpty
          ? anchorWordText
          : null,
    );
  }
}
