import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

/// Root application widget with theme configuration.
class NamerApp extends StatelessWidget {
  const NamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chord Namer',
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    // Define custom colors based on Namer's design
    const primary = Color(0xFF00E5FF);        // Bright cyan
    const secondary = Color(0xFFB040FF);      // Purple
    const surfaceColor = Color(0xFF121212);   // Very dark gray (background)
    const surfaceContainer = Color(0xFF1A1A1A); // Dark gray (panels)
    const surfaceVariant = Color(0xFF2A2A2A);  // Medium gray (buttons)
    const onSurface = Color(0xFFE0E0E0);      // Light gray (text)
    const onSurfaceVariant = Color(0xFF808080); // Medium gray (labels)
    
    return ThemeData.dark(
      useMaterial3: true,
    ).copyWith(
      scaffoldBackgroundColor: surfaceColor,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surfaceColor,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        surfaceContainerHighest: surfaceContainer,
        surfaceContainerHigh: surfaceVariant,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: surfaceVariant,
          foregroundColor: onSurface,
        ),
      ),
    );
  }
}
