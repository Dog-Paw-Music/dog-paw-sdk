/// Shared command contract for Home Screen cross-app interactions.
abstract final class HomeScreenCommands {
  /// Command name for toggling whether developer-only apps are shown.
  static const String toggleDeveloperAppsVisibility =
      'toggle_developer_apps_visibility';

  /// Result payload key reporting the updated visibility mode after a toggle.
  static const String showDeveloperAppsResultKey = 'showDeveloperApps';

  /// Purpose:
  /// Build user-facing snackbar text for the Home Screen's developer-app
  /// visibility state.
  ///
  /// Parameters:
  /// - [showDeveloperApps]: `true` when developer-only apps are currently
  ///   visible; `false` when they are hidden.
  ///
  /// Return value:
  /// - `String` status text suitable for a snackbar.
  ///
  /// Requirements/Preconditions:
  /// - [showDeveloperApps] must describe the Home Screen's post-toggle state.
  ///
  /// Guarantees/Postconditions:
  /// - Returns one stable message string for each visibility mode.
  ///
  /// Invariants:
  /// - Does not inspect UI state or mutate command payloads.
  static String visibilitySnackbarMessage(bool showDeveloperApps) {
    return showDeveloperApps
        ? 'Developer apps visible'
        : 'Developer apps hidden';
  }
}
