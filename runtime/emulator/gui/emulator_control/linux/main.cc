#include "my_application.h"

/**
 * @brief Starts the Flutter Linux shell for the emulator control GUI.
 *
 * Purpose: hands command-line arguments to the GTK/Flutter application wrapper
 * generated for this desktop developer tool.
 *
 * @param argc Number of process arguments supplied by the operating system.
 * Must be non-negative.
 * @param argv Process argument array. Must contain at least the binary name
 * when argc is greater than zero.
 * @return GTK application exit code.
 *
 * @pre GTK and Flutter Linux runtime libraries are available.
 * @post The application has run until normal shutdown or startup failure.
 * @invariant Does not register this GUI as a Dog Paw app.
 */
int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
