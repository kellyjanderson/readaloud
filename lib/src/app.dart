import 'package:flutter/material.dart';

import 'controllers/reader_controller.dart';
import 'screens/read_aloud_screen.dart';
import 'services/app_launch_options.dart';
import 'theme/read_aloud_theme.dart';
import 'widgets/reader_status_toast.dart';

class ReadAloudApp extends StatefulWidget {
  const ReadAloudApp({
    super.key,
    this.launchOptions = const AppLaunchOptions(),
    this.controller,
  });

  final AppLaunchOptions launchOptions;
  final ReaderController? controller;

  @override
  State<ReadAloudApp> createState() => _ReadAloudAppState();
}

class _ReadAloudAppState extends State<ReadAloudApp> {
  late final ReaderController _controller =
      widget.controller ?? ReaderController();

  ThemeData _buildLightTheme() {
    const tokens = ReadAloudThemeTokens.light;
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF2C7A74),
      onPrimary: Color(0xFFFBF8F2),
      secondary: Color(0xFF5FB1AA),
      onSecondary: Color(0xFF102026),
      error: Color(0xFF7A2E2E),
      onError: Color(0xFFFBF8F2),
      surface: Color(0xFFFCFAF5),
      onSurface: Color(0xFF1F2730),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.appBackground,
      fontFamily: kUiFontFamily,
      extensions: const <ThemeExtension<dynamic>>[tokens],
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.appBackground,
      fontFamily: kUiFontFamily,
      extensions: const <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontFamily: kUiFontFamily,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.dialogSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: tokens.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.dialogSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.elevatedSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.elevatedSurface,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: base.textTheme.labelMedium?.copyWith(
          fontFamily: kUiFontFamily,
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.dialogSurface,
        labelStyle: base.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF58636D),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2C7A74), width: 1.4),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 24,
      ),
      textTheme: base.textTheme
          .copyWith(
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: base.textTheme.titleSmall?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: base.textTheme.bodyLarge?.copyWith(
              fontFamily: kUiFontFamily,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              fontFamily: kUiFontFamily,
              color: colorScheme.onSurface,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              fontFamily: kUiFontFamily,
              color: const Color(0xFF58636D),
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: base.textTheme.labelMedium?.copyWith(
              fontFamily: kUiFontFamily,
            ),
          )
          .apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          ),
    );
  }

  ThemeData _buildDarkTheme() {
    const tokens = ReadAloudThemeTokens.dark;
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF5FB1AA),
      onPrimary: Color(0xFF102026),
      secondary: Color(0xFFD4EBE8),
      onSecondary: Color(0xFF102026),
      error: Color(0xFFF5D7D9),
      onError: Color(0xFF4B2326),
      surface: Color(0xFF202A34),
      onSurface: Color(0xFFE8E0D3),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.appBackground,
      fontFamily: kUiFontFamily,
      extensions: const <ThemeExtension<dynamic>>[tokens],
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.appBackground,
      fontFamily: kUiFontFamily,
      extensions: const <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontFamily: kUiFontFamily,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.dialogSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: tokens.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.dialogSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.elevatedSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.elevatedSurface,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: base.textTheme.labelMedium?.copyWith(
          fontFamily: kUiFontFamily,
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.dialogSurface,
        labelStyle: base.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB4BEC7),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF5FB1AA), width: 1.4),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 24,
      ),
      textTheme: base.textTheme
          .copyWith(
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: base.textTheme.titleSmall?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: base.textTheme.bodyLarge?.copyWith(
              fontFamily: kUiFontFamily,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              fontFamily: kUiFontFamily,
              color: colorScheme.onSurface,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              fontFamily: kUiFontFamily,
              color: const Color(0xFFB4BEC7),
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              fontFamily: kUiFontFamily,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: base.textTheme.labelMedium?.copyWith(
              fontFamily: kUiFontFamily,
            ),
          )
          .apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          ),
    );
  }

  @override
  void dispose() {
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
        final status = _controller.statusMessage;
        final toastMessage = status == null
            ? null
            : sanitizeReaderStatusMessage(status);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Read Aloud',
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: _controller.appearanceMode.themeMode,
          builder: (context, child) {
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (toastMessage != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(36, 12, 36, 0),
                        child: ReaderStatusToast(
                          key: const Key('status-toast'),
                          message: toastMessage,
                          style: toastStyleForStatus(
                            context: context,
                            message: status!,
                          ),
                          onDismiss: () {
                            _controller.clearStatus();
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          home: ReadAloudScreen(
            controller: _controller,
            initialInputPaths: widget.launchOptions.inputPaths,
          ),
        );
      },
    );
  }
}
