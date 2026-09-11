import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/hello_controller.dart';

// =============================================================================
// Touchscreen UI for Hello Dog Paw
//
// This file only draws widgets. All Dog Paw logic lives in HelloController.
// =============================================================================

/// Root MaterialApp for the first Dog Paw teaching example.
class HelloDogPawApp extends StatelessWidget {
  const HelloDogPawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hello Dog Paw',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF673AB7),
          brightness: Brightness.dark,
        ),
      ),
      home: const HelloDogPawHomeScreen(),
    );
  }
}

/// Single screen: connection status plus two color rows.
class HelloDogPawHomeScreen extends StatefulWidget {
  const HelloDogPawHomeScreen({super.key});

  @override
  State<HelloDogPawHomeScreen> createState() => _HelloDogPawHomeScreenState();
}

class _HelloDogPawHomeScreenState extends State<HelloDogPawHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Start Dog Paw after the first frame so Provider is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<HelloController>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final HelloController controller = context.watch<HelloController>();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color statusColor = controller.isReady
        ? colorScheme.tertiary
        : controller.isStarting
        ? colorScheme.secondary
        : colorScheme.error;
    final String statusLabel = controller.isReady
        ? 'Live'
        : controller.isStarting
        ? 'Starting'
        : 'Waiting';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hello Dog Paw'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This hello example lights each key according to its '
                      'play state and the colors you pick below.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(Icons.circle, size: 14, color: statusColor),
                        Text(
                          '$statusLabel: ${controller.statusMessage}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _HelloSwatchRowCard(
                      title: 'Active Keys',
                      description:
                          'Keys that are slightly pressed, but have not made '
                          'contact with the bottom yet.',
                      state: HelloHighlightState.active,
                    ),
                    const SizedBox(height: 16),
                    const _HelloSwatchRowCard(
                      title: 'Pressed Keys',
                      description:
                          'Keys that have made contact with the bottom.',
                      state: HelloHighlightState.pressed,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Keys at rest clear their highlight.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One titled row of color chips bound to a highlight state.
class _HelloSwatchRowCard extends StatelessWidget {
  const _HelloSwatchRowCard({
    required this.title,
    required this.description,
    required this.state,
  });

  final String title;
  final String description;
  final HelloHighlightState state;

  @override
  Widget build(BuildContext context) {
    final HelloController controller = context.watch<HelloController>();
    final int selectedColor = controller.colorForState(state);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: controller.availableSwatches.map((HelloColorSwatch swatch) {
                return ChoiceChip(
                  label: Text(swatch.label),
                  selected: selectedColor == swatch.colorArgb,
                  avatar: CircleAvatar(
                    backgroundColor: Color(swatch.colorArgb),
                  ),
                  onSelected: (_) {
                    controller.selectColor(state, swatch.colorArgb);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
