import 'package:flutter/material.dart';

import 'screens/read_aloud_screen.dart';

class ReadAloudApp extends StatelessWidget {
  const ReadAloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF005F73),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF2F0EA),
      useMaterial3: true,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: const Color(0xFF1F2933),
        displayColor: const Color(0xFF1F2933),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Read Aloud',
      theme: theme,
      home: const ReadAloudScreen(),
    );
  }
}
