import 'package:dogpaw/dogpaw.dart' as dp;

/// Tracks the retained key highlights owned by the Namer app.
///
/// This helper sits between `NamerService` and the Dog Paw LED message
/// protocol. It owns the animation instance ids for the app's "show me"
/// highlights so the service can replace or clear them without reaching for
/// the legacy solid-key surface.
class NamerHighlightTracker {
  /// Creates one tracker for the Namer app's retained note highlights.
  ///
  /// Parameters:
  /// - [allocator]: optional animation-id allocator used to create ids that do
  ///   not collide with other retained highlight producers.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The tracker is ready to plan highlight create/cancel messages.
  ///
  /// Invariants:
  /// - Active animation ids remain paired with their key coordinates until they
  ///   are explicitly cancelled.
  NamerHighlightTracker({dp.LedClientAnimIdAllocator? allocator})
      : _allocator = allocator ?? dp.LedClientAnimIdAllocator();

  final dp.LedClientAnimIdAllocator _allocator;
  final Map<(int, int), int> _animationIdsByKey = <(int, int), int>{};

  /// Plans the retained highlight updates needed to match [keys].
  ///
  /// Parameters:
  /// - [keys]: desired key coordinates to remain highlighted after the update.
  /// - [colorArgb]: packed AARRGGBB color used for any newly-created
  ///   highlights.
  ///
  /// Return value:
  /// - Ordered LED messages that first cancel removed highlights and then
  ///   create any missing highlights.
  ///
  /// Requirements/Preconditions:
  /// - Each tuple in [keys] must use Dog Paw key coordinates with
  ///   `0 <= col <= 7` and `0 <= row <= 7`.
  ///
  /// Guarantees/Postconditions:
  /// - After the caller sends the returned messages, the tracker's internal
  ///   state matches [keys].
  ///
  /// Invariants:
  /// - Existing highlights that are still desired keep their current animation
  ///   ids so later cancels target the right retained animation.
  List<dp.LEDMessage> replaceHighlightsForKeys({
    required Iterable<(int, int)> keys,
    required int colorArgb,
  }) {
    final List<(int, int)> desiredKeys = keys.toList();
    final Set<(int, int)> desiredKeySet = desiredKeys.toSet();
    final List<dp.LEDMessage> messages = <dp.LEDMessage>[];

    final List<(int, int)> removedKeys = _animationIdsByKey.keys
        .where(((int, int) key) => !desiredKeySet.contains(key))
        .toList();
    for (final (int, int) key in removedKeys) {
      final int animationId = _animationIdsByKey.remove(key)!;
      messages.add(dp.AnimationCancelLEDMessage(clientInstanceId: animationId));
    }

    for (final (int, int) key in desiredKeys) {
      if (_animationIdsByKey.containsKey(key)) {
        continue;
      }
      final int animationId = _allocator.next();
      _animationIdsByKey[key] = animationId;
      messages.add(
        dp.KeyHighlightLEDMessage(
          column: key.$1,
          row: key.$2,
          colorArgb: colorArgb,
          clientInstanceId: animationId,
        ),
      );
    }

    return messages;
  }

  /// Plans cancellation messages for every active Namer-owned highlight.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Cancel messages for all tracked highlight ids.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The tracker forgets every active highlight after this call returns.
  ///
  /// Invariants:
  /// - No new highlight ids are allocated during clearing.
  List<dp.LEDMessage> clearHighlights() {
    final List<int> animationIds = _animationIdsByKey.values.toList();
    _animationIdsByKey.clear();
    return animationIds
        .map(
          (int animationId) =>
              dp.AnimationCancelLEDMessage(clientInstanceId: animationId),
        )
        .toList();
  }
}
