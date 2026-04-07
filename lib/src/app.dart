import 'package:flutter/material.dart';

import 'controllers/reader_controller.dart';
import 'screens/read_aloud_screen.dart';
import 'services/app_launch_options.dart';

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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF005F73),
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFF7F4EE),
      onSurface: const Color(0xFF1F2933),
      surfaceContainerHighest: const Color(0xFFEDE7DA),
    );
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF2F0EA),
      useMaterial3: true,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE9C46A),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF171B22),
      onSurface: const Color(0xFFE8EDF5),
      surfaceContainerHighest: const Color(0xFF202734),
    );
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF111827),
      useMaterial3: true,
      textTheme: ThemeData.dark().textTheme.apply(
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
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Read Aloud',
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: _controller.appearanceMode.themeMode,
          home: ReadAloudScreen(
            controller: _controller,
            initialInputPaths: widget.launchOptions.inputPaths,
          ),
        );
      },
    );
  }
}
