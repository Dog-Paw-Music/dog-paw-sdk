import 'package:flutter/material.dart';

import 'screens/pond_screen.dart';

/// Root widget and lofi color scheme for Rain Pond.
class RainPondApp extends StatelessWidget {
  const RainPondApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rain Pond',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF152028),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7EC8E3),
          secondary: Color(0xFFC9B8A8),
          surface: Color(0xFF1E2D38),
          onSurface: Color(0xFFE8F4FC),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
      ),
      home: const PondScreen(),
    );
  }
}
