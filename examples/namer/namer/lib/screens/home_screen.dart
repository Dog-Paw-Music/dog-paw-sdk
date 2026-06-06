import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/home_controller.dart';
import '../widgets/chord_display_panel.dart';
import '../widgets/chord_builder_panel.dart';
import '../widgets/show_me_button.dart';

/// Main screen for the Namer app.
/// 
/// Displays chord detection, chord building interface, and LED controls.
/// Business logic is handled by HomeController via Provider.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Delay initialization until after the first frame to avoid calling
    // notifyListeners() during the initial widget build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeController();
      }
    });
  }
  
  Future<void> _initializeController() async {
    final controller = context.read<HomeController>();
    final connectionHandle = await controller.initialize();
    
    // Signal ready to Epiphany after initialization
    if (connectionHandle != null && mounted) {
      await connectionHandle.complete();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<HomeController>(
      builder: (context, controller, child) {
        final theme = Theme.of(context);
        
        if (controller.isLoading) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Connecting to DogPaw server...',
                    style: TextStyle(fontSize: 18, color: Colors.orange),
                  ),
                ],
              ),
            ),
          );
        }
        
        if (!controller.isConnected) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to connect to DogPaw server',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Chord Namer',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  controller.isConnected ? Icons.check_circle : Icons.error,
                  color: controller.isConnected ? theme.colorScheme.primary : Colors.red,
                ),
              )
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left column: Chord display + Show Me button (25%)
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chord display (takes 2/3 of height)
                      Expanded(
                        flex: 2,
                        child: ChordDisplayPanel(
                          heldNotes: controller.physicallyHeldNotes,
                          useJazzNotation: controller.useJazzNotation,
                          onToggleNamingScheme: controller.toggleNamingScheme,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Show Me button (takes 1/3 of height)
                      Expanded(
                        flex: 1,
                        child: ShowMeButton(
                          onPressed: controller.highlightNotes,
                          onReleased: controller.clearHighlights,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Right panel: Chord builder (75%)
                Expanded(
                  flex: 3,
                  child: ChordBuilderPanel(
                    selectedNotes: controller.selectedNotes,
                    physicallyHeldNotes: controller.physicallyHeldNotes,
                    onNotesChanged: controller.selectNotes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
