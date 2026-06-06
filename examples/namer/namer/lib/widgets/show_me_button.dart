import 'package:flutter/material.dart';

/// Large button for highlighting selected notes on the physical keyboard.
/// 
/// This button sends LED messages while pressed and clears them on release.
/// Uses gesture detection to handle press/release/cancel events.
class ShowMeButton extends StatelessWidget {
  /// Called when the button is pressed down
  final VoidCallback onPressed;
  
  /// Called when the button is released (tap up or cancel)
  final VoidCallback onReleased;
  
  const ShowMeButton({
    super.key,
    required this.onPressed,
    required this.onReleased,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp: (_) => onReleased(),
      onTapCancel: onReleased,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SHOW ME',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
