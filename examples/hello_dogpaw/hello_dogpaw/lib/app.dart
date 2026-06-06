import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/hello_controller.dart';

/// Purpose:
///     Root MaterialApp for the first Dog Paw teaching example.
/// Parameters:
///     key: Standard Flutter widget key.
/// Return value:
///     Stateless widget that renders the hello-example home screen.
/// Requirements:
///     A HelloController must already be available above this widget in the
///     widget tree.
/// Guarantees:
///     Presents one minimal screen that explains the example and exposes the
///     connect action.
/// Invariants:
///     Keeps app-level theme and routing separate from connection logic.
class HelloDogPawApp extends StatelessWidget {
  /// Purpose:
  ///     Construct the root app widget.
  /// Parameters:
  ///     key: Standard Flutter widget key.
  /// Return value:
  ///     New HelloDogPawApp widget.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Widget is immutable after construction.
  /// Invariants:
  ///     Contains no runtime side effects.
  const HelloDogPawApp({super.key});

  /// Purpose:
  ///     Build the hello-example MaterialApp and home scaffold.
  /// Parameters:
  ///     context: Flutter build context for inherited theme and providers.
  /// Return value:
  ///     Configured MaterialApp for the hello example.
  /// Requirements:
  ///     None beyond normal Flutter build rules.
  /// Guarantees:
  ///     Renders one home screen with a compact dark theme.
  /// Invariants:
  ///     Does not perform connection work directly.
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

/// Purpose:
///     Single teaching screen for the minimal Dog Paw LED example.
/// Parameters:
///     key: Standard Flutter widget key.
/// Return value:
///     Stateful widget that auto-starts the controller and renders the color UI.
/// Requirements:
///     `HelloController` must be available from `Provider`.
/// Guarantees:
///     Triggers startup after the first frame and keeps runtime logic out of the
///     widget tree.
/// Invariants:
///     UI remains declarative after the startup callback is scheduled.
class HelloDogPawHomeScreen extends StatefulWidget {
  /// Purpose:
  ///     Construct the hello-example home screen.
  /// Parameters:
  ///     key: Standard Flutter widget key.
  /// Return value:
  ///     New `HelloDogPawHomeScreen` widget.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Widget is immutable after construction.
  /// Invariants:
  ///     Contains no runtime side effects by itself.
  const HelloDogPawHomeScreen({super.key});

  /// Purpose:
  ///     Create the mutable state object that schedules startup.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     New `_HelloDogPawHomeScreenState`.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     The returned state owns the one-time startup callback.
  /// Invariants:
  ///     Always returns the same state type for this widget.
  @override
  State<HelloDogPawHomeScreen> createState() => _HelloDogPawHomeScreenState();
}

/// Purpose:
///     Stateful host that schedules `HelloController.start()` once after mount.
/// Parameters:
///     None.
/// Return value:
///     State object for `HelloDogPawHomeScreen`.
/// Requirements:
///     `HelloController` must be available from `Provider` above this widget.
/// Guarantees:
///     Startup is requested exactly once per mounted home screen.
/// Invariants:
///     Does not own any additional business logic beyond startup scheduling.
class _HelloDogPawHomeScreenState extends State<HelloDogPawHomeScreen> {
  /// Purpose:
  ///     Schedule the hello controller startup after the first frame.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `Provider<HelloController>` must already be present in the tree.
  /// Guarantees:
  ///     Calls `HelloController.start()` once without triggering side effects
  ///     during widget construction.
  /// Invariants:
  ///     Leaves the widget mounted-state rules unchanged.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<HelloController>().start();
    });
  }

  /// Purpose:
  ///     Build the hello-example teaching screen from controller state.
  /// Parameters:
  ///     context: Flutter build context for inherited theme and providers.
  /// Return value:
  ///     Scaffold showing status plus active/pressed color controls.
  /// Requirements:
  ///     `HelloController` must be readable from `Provider`.
  /// Guarantees:
  ///     Reflects live controller status and selected colors without handling
  ///     runtime work directly.
  /// Invariants:
  ///     The UI never mutates controller state except through color selection.
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
                      'This hello example auto-connects on startup, listens to '
                      'key messages, and sends retained LED highlight updates '
                      'through the public Dog Paw wire surface.',
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
                    _HelloSwatchRowCard(
                      title: 'Active Keys',
                      description:
                          'Activated keys send a retained highlight create or '
                          'color update.',
                      state: HelloHighlightState.active,
                    ),
                    const SizedBox(height: 16),
                    _HelloSwatchRowCard(
                      title: 'Pressed Keys',
                      description:
                          'Pressed keys reuse the same retained animation id and '
                          'update it to the pressed color.',
                      state: HelloHighlightState.pressed,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Rest state clears the retained highlight instead of '
                      'sending a third color.',
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

/// Purpose:
///     One titled card row for selecting the hello example's highlight colors.
/// Parameters:
///     title: User-facing row title.
///     description: Short explanation of when this color is used.
///     state: Highlight family controlled by this row.
/// Return value:
///     Stateless widget rendering four selectable swatches.
/// Requirements:
///     `HelloController` must be available from `Provider`.
/// Guarantees:
///     Calls `selectColor()` when the user chooses a new swatch.
/// Invariants:
///     Contains presentation only; no runtime polling logic lives here.
class _HelloSwatchRowCard extends StatelessWidget {
  /// Purpose:
  ///     Construct one titled swatch-selection card.
  /// Parameters:
  ///     key: Standard Flutter widget key.
  ///     title: User-facing row title.
  ///     description: Short explanatory copy for the row.
  ///     state: Highlight family controlled by the row.
  /// Return value:
  ///     New `_HelloSwatchRowCard` widget.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Stores the supplied title, description, and state unchanged.
  /// Invariants:
  ///     Widget is immutable after construction.
  const _HelloSwatchRowCard({
    required this.title,
    required this.description,
    required this.state,
  });

  final String title;
  final String description;
  final HelloHighlightState state;

  /// Purpose:
  ///     Build the swatch row from the controller's current selection.
  /// Parameters:
  ///     context: Flutter build context for inherited theme and provider access.
  /// Return value:
  ///     Card section containing the row title, description, and swatches.
  /// Requirements:
  ///     `HelloController` must be readable from `Provider`.
  /// Guarantees:
  ///     Exactly one swatch is marked selected for this row.
  /// Invariants:
  ///     Never mutates controller state except via the `onSelected` callback.
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
