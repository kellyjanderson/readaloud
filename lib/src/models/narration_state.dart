class NarrationState {
  const NarrationState({
    required this.sessionId,
    required this.currentSectionMode,
    required this.discourseMode,
    required this.recentBoundaryClass,
    required this.continuationPending,
    required this.recentEmphasisDensity,
    required this.recentRate,
    required this.quoteMode,
    required this.localPronunciationChoices,
  });

  factory NarrationState.initial({double recentRate = 1.0}) {
    return NarrationState(
      sessionId: _newSessionId(),
      currentSectionMode: null,
      discourseMode: null,
      recentBoundaryClass: null,
      continuationPending: false,
      recentEmphasisDensity: 0.0,
      recentRate: recentRate,
      quoteMode: null,
      localPronunciationChoices: const <String, String>{},
    );
  }

  final String sessionId;
  final String? currentSectionMode;
  final String? discourseMode;
  final String? recentBoundaryClass;
  final bool continuationPending;
  final double recentEmphasisDensity;
  final double recentRate;
  final String? quoteMode;
  final Map<String, String> localPronunciationChoices;

  NarrationState reset({double recentRate = 1.0}) {
    return NarrationState.initial(recentRate: recentRate);
  }

  NarrationState copyWith({
    String? sessionId,
    String? currentSectionMode,
    String? discourseMode,
    String? recentBoundaryClass,
    bool? continuationPending,
    double? recentEmphasisDensity,
    double? recentRate,
    String? quoteMode,
    Map<String, String>? localPronunciationChoices,
  }) {
    return NarrationState(
      sessionId: sessionId ?? this.sessionId,
      currentSectionMode: currentSectionMode ?? this.currentSectionMode,
      discourseMode: discourseMode ?? this.discourseMode,
      recentBoundaryClass: recentBoundaryClass ?? this.recentBoundaryClass,
      continuationPending: continuationPending ?? this.continuationPending,
      recentEmphasisDensity:
          recentEmphasisDensity ?? this.recentEmphasisDensity,
      recentRate: recentRate ?? this.recentRate,
      quoteMode: quoteMode ?? this.quoteMode,
      localPronunciationChoices:
          localPronunciationChoices ?? this.localPronunciationChoices,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sessionId': sessionId,
      'currentSectionMode': currentSectionMode,
      'discourseMode': discourseMode,
      'recentBoundaryClass': recentBoundaryClass,
      'continuationPending': continuationPending,
      'recentEmphasisDensity': recentEmphasisDensity,
      'recentRate': recentRate,
      'quoteMode': quoteMode,
      'localPronunciationChoices': localPronunciationChoices,
    };
  }
}

String _newSessionId() => 'ns_${DateTime.now().microsecondsSinceEpoch}';
