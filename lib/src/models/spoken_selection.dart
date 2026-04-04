enum SpokenSelectionPrecision {
  none,
  word,
  segment,
  block,
}

class SpokenSelection {
  const SpokenSelection({
    required this.precision,
    required this.confidence,
    this.segmentId,
    this.displayBlockId,
    this.displayStart,
    this.displayEnd,
    this.speechStartWordIndex,
    this.speechEndWordIndex,
    this.voiceId,
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  const SpokenSelection.none()
    : precision = SpokenSelectionPrecision.none,
      confidence = 0.0,
      segmentId = null,
      displayBlockId = null,
      displayStart = null,
      displayEnd = null,
      speechStartWordIndex = null,
      speechEndWordIndex = null,
      voiceId = null,
      routeId = null,
      castId = null,
      dialogueSpanId = null;

  final SpokenSelectionPrecision precision;
  final double confidence;
  final String? segmentId;
  final String? displayBlockId;
  final int? displayStart;
  final int? displayEnd;
  final int? speechStartWordIndex;
  final int? speechEndWordIndex;
  final String? voiceId;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;

  bool get hasSelection => precision != SpokenSelectionPrecision.none;
}
