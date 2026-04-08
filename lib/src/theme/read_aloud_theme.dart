import 'package:flutter/material.dart';

const String kUiFontFamily = 'Source Sans 3';
const String kReadingFontFamily = 'Source Serif 4';
const String kTechnicalFontFamily = 'IBM Plex Mono';

@immutable
class ReadAloudThemeTokens extends ThemeExtension<ReadAloudThemeTokens> {
  const ReadAloudThemeTokens({
    required this.appBackground,
    required this.chromeSurface,
    required this.readerSurface,
    required this.dialogSurface,
    required this.elevatedSurface,
    required this.technicalSurface,
    required this.technicalOnSurface,
    required this.border,
    required this.readerBorder,
    required this.dropOverlaySurface,
    required this.dropOverlayBorder,
    required this.processingScrim,
    required this.processingSurface,
    required this.processingBorder,
    required this.embeddedContextSurface,
    required this.embeddedContextBorder,
    required this.activeReadingBlock,
    required this.spokenWordBackground,
    required this.spokenWordText,
    required this.spokenSegmentBackground,
    required this.spokenBlockBackground,
    required this.spokenBlockBorder,
    required this.infoToastBackground,
    required this.infoToastForeground,
    required this.warningToastBackground,
    required this.warningToastForeground,
    required this.errorToastBackground,
    required this.errorToastForeground,
    required this.qualityBadgeBackground,
    required this.qualityBadgeForeground,
    required this.metadataPillBackground,
    required this.metadataPillForeground,
    required this.surfaceShadow,
  });

  final Color appBackground;
  final Color chromeSurface;
  final Color readerSurface;
  final Color dialogSurface;
  final Color elevatedSurface;
  final Color technicalSurface;
  final Color technicalOnSurface;
  final Color border;
  final Color readerBorder;
  final Color dropOverlaySurface;
  final Color dropOverlayBorder;
  final Color processingScrim;
  final Color processingSurface;
  final Color processingBorder;
  final Color embeddedContextSurface;
  final Color embeddedContextBorder;
  final Color activeReadingBlock;
  final Color spokenWordBackground;
  final Color spokenWordText;
  final Color spokenSegmentBackground;
  final Color spokenBlockBackground;
  final Color spokenBlockBorder;
  final Color infoToastBackground;
  final Color infoToastForeground;
  final Color warningToastBackground;
  final Color warningToastForeground;
  final Color errorToastBackground;
  final Color errorToastForeground;
  final Color qualityBadgeBackground;
  final Color qualityBadgeForeground;
  final Color metadataPillBackground;
  final Color metadataPillForeground;
  final Color surfaceShadow;

  static const light = ReadAloudThemeTokens(
    appBackground: Color(0xFFF4EFE6),
    chromeSurface: Color(0xFFEFE7D8),
    readerSurface: Color(0xFFFCFAF5),
    dialogSurface: Color(0xFFFCFAF5),
    elevatedSurface: Color(0xFFF6F1E8),
    technicalSurface: Color(0xFF1F2730),
    technicalOnSurface: Color(0xFFFBF8F2),
    border: Color(0xFFD5CCBB),
    readerBorder: Color(0xFFDAD2C5),
    dropOverlaySurface: Color(0xE6F6F1E8),
    dropOverlayBorder: Color(0xFFD6A84A),
    processingScrim: Color(0xCCF4EFE6),
    processingSurface: Color(0xFFFCFAF5),
    processingBorder: Color(0xFFD5CCBB),
    embeddedContextSurface: Color(0xFFF6F1E8),
    embeddedContextBorder: Color(0xFFD5CCBB),
    activeReadingBlock: Color(0x1AF1D289),
    spokenWordBackground: Color(0xFFD6A84A),
    spokenWordText: Color(0xFF1F2730),
    spokenSegmentBackground: Color(0x55F1D289),
    spokenBlockBackground: Color(0x29F1D289),
    spokenBlockBorder: Color(0xFFD6A84A),
    infoToastBackground: Color(0xFFDCEBE8),
    infoToastForeground: Color(0xFF1F5D59),
    warningToastBackground: Color(0xFFFAE7B8),
    warningToastForeground: Color(0xFF6F4D11),
    errorToastBackground: Color(0xFFF4D3D3),
    errorToastForeground: Color(0xFF7A2E2E),
    qualityBadgeBackground: Color(0xFFDCEBE8),
    qualityBadgeForeground: Color(0xFF1F5D59),
    metadataPillBackground: Color(0xFFE9E2D5),
    metadataPillForeground: Color(0xFF4D5862),
    surfaceShadow: Color(0x18000000),
  );

  static const dark = ReadAloudThemeTokens(
    appBackground: Color(0xFF0F141A),
    chromeSurface: Color(0xFF151B22),
    readerSurface: Color(0xFF1A222B),
    dialogSurface: Color(0xFF202A34),
    elevatedSurface: Color(0xFF26313C),
    technicalSurface: Color(0xFF0F141A),
    technicalOnSurface: Color(0xFFE8E0D3),
    border: Color(0xFF34424E),
    readerBorder: Color(0xFF34424E),
    dropOverlaySurface: Color(0xD9151B22),
    dropOverlayBorder: Color(0xFFB9892D),
    processingScrim: Color(0xCC0F141A),
    processingSurface: Color(0xFF202A34),
    processingBorder: Color(0xFF34424E),
    embeddedContextSurface: Color(0xFF26313C),
    embeddedContextBorder: Color(0xFF34424E),
    activeReadingBlock: Color(0x227F6226),
    spokenWordBackground: Color(0xFFB9892D),
    spokenWordText: Color(0xFF15120D),
    spokenSegmentBackground: Color(0x557F6226),
    spokenBlockBackground: Color(0x337F6226),
    spokenBlockBorder: Color(0xFFB9892D),
    infoToastBackground: Color(0xFF1F3A3A),
    infoToastForeground: Color(0xFFD7ECEA),
    warningToastBackground: Color(0xFF4A3614),
    warningToastForeground: Color(0xFFF7E0B2),
    errorToastBackground: Color(0xFF4B2326),
    errorToastForeground: Color(0xFFF5D7D9),
    qualityBadgeBackground: Color(0xFF214140),
    qualityBadgeForeground: Color(0xFFD7ECEA),
    metadataPillBackground: Color(0xFF2A3642),
    metadataPillForeground: Color(0xFFD4DDD6),
    surfaceShadow: Color(0x40000000),
  );

  @override
  ReadAloudThemeTokens copyWith({
    Color? appBackground,
    Color? chromeSurface,
    Color? readerSurface,
    Color? dialogSurface,
    Color? elevatedSurface,
    Color? technicalSurface,
    Color? technicalOnSurface,
    Color? border,
    Color? readerBorder,
    Color? dropOverlaySurface,
    Color? dropOverlayBorder,
    Color? processingScrim,
    Color? processingSurface,
    Color? processingBorder,
    Color? embeddedContextSurface,
    Color? embeddedContextBorder,
    Color? activeReadingBlock,
    Color? spokenWordBackground,
    Color? spokenWordText,
    Color? spokenSegmentBackground,
    Color? spokenBlockBackground,
    Color? spokenBlockBorder,
    Color? infoToastBackground,
    Color? infoToastForeground,
    Color? warningToastBackground,
    Color? warningToastForeground,
    Color? errorToastBackground,
    Color? errorToastForeground,
    Color? qualityBadgeBackground,
    Color? qualityBadgeForeground,
    Color? metadataPillBackground,
    Color? metadataPillForeground,
    Color? surfaceShadow,
  }) {
    return ReadAloudThemeTokens(
      appBackground: appBackground ?? this.appBackground,
      chromeSurface: chromeSurface ?? this.chromeSurface,
      readerSurface: readerSurface ?? this.readerSurface,
      dialogSurface: dialogSurface ?? this.dialogSurface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      technicalSurface: technicalSurface ?? this.technicalSurface,
      technicalOnSurface: technicalOnSurface ?? this.technicalOnSurface,
      border: border ?? this.border,
      readerBorder: readerBorder ?? this.readerBorder,
      dropOverlaySurface: dropOverlaySurface ?? this.dropOverlaySurface,
      dropOverlayBorder: dropOverlayBorder ?? this.dropOverlayBorder,
      processingScrim: processingScrim ?? this.processingScrim,
      processingSurface: processingSurface ?? this.processingSurface,
      processingBorder: processingBorder ?? this.processingBorder,
      embeddedContextSurface:
          embeddedContextSurface ?? this.embeddedContextSurface,
      embeddedContextBorder:
          embeddedContextBorder ?? this.embeddedContextBorder,
      activeReadingBlock: activeReadingBlock ?? this.activeReadingBlock,
      spokenWordBackground:
          spokenWordBackground ?? this.spokenWordBackground,
      spokenWordText: spokenWordText ?? this.spokenWordText,
      spokenSegmentBackground:
          spokenSegmentBackground ?? this.spokenSegmentBackground,
      spokenBlockBackground:
          spokenBlockBackground ?? this.spokenBlockBackground,
      spokenBlockBorder: spokenBlockBorder ?? this.spokenBlockBorder,
      infoToastBackground:
          infoToastBackground ?? this.infoToastBackground,
      infoToastForeground:
          infoToastForeground ?? this.infoToastForeground,
      warningToastBackground:
          warningToastBackground ?? this.warningToastBackground,
      warningToastForeground:
          warningToastForeground ?? this.warningToastForeground,
      errorToastBackground:
          errorToastBackground ?? this.errorToastBackground,
      errorToastForeground:
          errorToastForeground ?? this.errorToastForeground,
      qualityBadgeBackground:
          qualityBadgeBackground ?? this.qualityBadgeBackground,
      qualityBadgeForeground:
          qualityBadgeForeground ?? this.qualityBadgeForeground,
      metadataPillBackground:
          metadataPillBackground ?? this.metadataPillBackground,
      metadataPillForeground:
          metadataPillForeground ?? this.metadataPillForeground,
      surfaceShadow: surfaceShadow ?? this.surfaceShadow,
    );
  }

  @override
  ThemeExtension<ReadAloudThemeTokens> lerp(
    covariant ThemeExtension<ReadAloudThemeTokens>? other,
    double t,
  ) {
    if (other is! ReadAloudThemeTokens) {
      return this;
    }
    return ReadAloudThemeTokens(
      appBackground: Color.lerp(appBackground, other.appBackground, t)!,
      chromeSurface: Color.lerp(chromeSurface, other.chromeSurface, t)!,
      readerSurface: Color.lerp(readerSurface, other.readerSurface, t)!,
      dialogSurface: Color.lerp(dialogSurface, other.dialogSurface, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      technicalSurface:
          Color.lerp(technicalSurface, other.technicalSurface, t)!,
      technicalOnSurface:
          Color.lerp(technicalOnSurface, other.technicalOnSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      readerBorder: Color.lerp(readerBorder, other.readerBorder, t)!,
      dropOverlaySurface:
          Color.lerp(dropOverlaySurface, other.dropOverlaySurface, t)!,
      dropOverlayBorder:
          Color.lerp(dropOverlayBorder, other.dropOverlayBorder, t)!,
      processingScrim:
          Color.lerp(processingScrim, other.processingScrim, t)!,
      processingSurface:
          Color.lerp(processingSurface, other.processingSurface, t)!,
      processingBorder:
          Color.lerp(processingBorder, other.processingBorder, t)!,
      embeddedContextSurface:
          Color.lerp(embeddedContextSurface, other.embeddedContextSurface, t)!,
      embeddedContextBorder:
          Color.lerp(embeddedContextBorder, other.embeddedContextBorder, t)!,
      activeReadingBlock:
          Color.lerp(activeReadingBlock, other.activeReadingBlock, t)!,
      spokenWordBackground:
          Color.lerp(spokenWordBackground, other.spokenWordBackground, t)!,
      spokenWordText: Color.lerp(spokenWordText, other.spokenWordText, t)!,
      spokenSegmentBackground: Color.lerp(
        spokenSegmentBackground,
        other.spokenSegmentBackground,
        t,
      )!,
      spokenBlockBackground: Color.lerp(
        spokenBlockBackground,
        other.spokenBlockBackground,
        t,
      )!,
      spokenBlockBorder:
          Color.lerp(spokenBlockBorder, other.spokenBlockBorder, t)!,
      infoToastBackground:
          Color.lerp(infoToastBackground, other.infoToastBackground, t)!,
      infoToastForeground:
          Color.lerp(infoToastForeground, other.infoToastForeground, t)!,
      warningToastBackground:
          Color.lerp(warningToastBackground, other.warningToastBackground, t)!,
      warningToastForeground:
          Color.lerp(warningToastForeground, other.warningToastForeground, t)!,
      errorToastBackground:
          Color.lerp(errorToastBackground, other.errorToastBackground, t)!,
      errorToastForeground:
          Color.lerp(errorToastForeground, other.errorToastForeground, t)!,
      qualityBadgeBackground:
          Color.lerp(qualityBadgeBackground, other.qualityBadgeBackground, t)!,
      qualityBadgeForeground:
          Color.lerp(qualityBadgeForeground, other.qualityBadgeForeground, t)!,
      metadataPillBackground:
          Color.lerp(metadataPillBackground, other.metadataPillBackground, t)!,
      metadataPillForeground:
          Color.lerp(metadataPillForeground, other.metadataPillForeground, t)!,
      surfaceShadow: Color.lerp(surfaceShadow, other.surfaceShadow, t)!,
    );
  }
}

ReadAloudThemeTokens readAloudThemeTokens(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<ReadAloudThemeTokens>() ??
      (theme.brightness == Brightness.dark
          ? ReadAloudThemeTokens.dark
          : ReadAloudThemeTokens.light);
}

String resolveReaderFontFamily(String preference) {
  return switch (preference) {
    'sans-serif' => kUiFontFamily,
    'monospace' => kTechnicalFontFamily,
    _ => kReadingFontFamily,
  };
}
