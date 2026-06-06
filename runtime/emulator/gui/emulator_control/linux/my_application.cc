#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

/**
 * @brief Creates and displays the Flutter GTK window.
 *
 * Purpose: implements `GApplication::activate` for the emulator control GUI's
 * Linux shell.
 *
 * @param application GTK application instance. Must be a `MyApplication`.
 * @return None.
 *
 * @pre Flutter Linux and GTK have been initialized by GApplication startup.
 * @post A 1280x720 window containing the Flutter view is shown.
 * @invariant Dart entrypoint arguments are forwarded unchanged.
 */
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "emulator_control");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "emulator_control");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

/**
 * @brief Captures command-line arguments before activation.
 *
 * Purpose: implements `GApplication::local_command_line` so Dart receives
 * emulator GUI arguments such as `--bridge-url=...`.
 *
 * @param application GTK application instance. Must be a `MyApplication`.
 * @param arguments Mutable process argument vector provided by GTK.
 * @param exit_status Output parameter for the process exit status.
 * @return TRUE because this function handles activation.
 *
 * @pre `arguments` and `exit_status` must be non-null.
 * @post On success, Dart entrypoint arguments are stored and the app activates.
 * @post On registration failure, `exit_status` is set to 1.
 * @invariant The original argument strings are copied before use.
 */
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

/**
 * @brief Runs GTK application startup.
 *
 * Purpose: implements `GApplication::startup` and delegates to the parent GTK
 * class for the generated Flutter shell.
 *
 * @param application GTK application instance.
 * @return None.
 *
 * @pre `application` must be a valid GTK application object.
 * @post Parent startup hooks have run.
 * @invariant No emulator bridge state is created here.
 */
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

/**
 * @brief Runs GTK application shutdown.
 *
 * Purpose: implements `GApplication::shutdown` and delegates cleanup to the
 * parent GTK class.
 *
 * @param application GTK application instance.
 * @return None.
 *
 * @pre `application` must be a valid GTK application object.
 * @post Parent shutdown hooks have run.
 * @invariant Does not send emulator bridge shutdown commands.
 */
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

/**
 * @brief Releases copied Dart entrypoint arguments.
 *
 * Purpose: implements `GObject::dispose` for the GTK application wrapper.
 *
 * @param object GObject instance. Must be a `MyApplication`.
 * @return None.
 *
 * @pre `object` must be valid for dispose.
 * @post Dart entrypoint argument storage is released.
 * @invariant Flutter project and view ownership remain GTK-managed.
 */
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

/**
 * @brief Registers GTK virtual method implementations.
 *
 * Purpose: wires the generated Flutter Linux shell into GTK object lifecycle
 * callbacks.
 *
 * @param klass Class object for `MyApplication`. Must be non-null.
 * @return None.
 *
 * @pre GTK type registration is in progress.
 * @post Activate, command-line, startup, shutdown, and dispose callbacks are
 * registered.
 * @invariant Callback ownership remains with GTK's type system.
 */
static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

/**
 * @brief Initializes one `MyApplication` instance.
 *
 * Purpose: provides the GTK instance initializer required by `G_DEFINE_TYPE`.
 *
 * @param self Application instance being initialized.
 * @return None.
 *
 * @pre `self` must be a freshly allocated `MyApplication`.
 * @post No additional instance state is initialized.
 * @invariant Dart entrypoint arguments remain null until command-line handling.
 */
static void my_application_init(MyApplication* self) {}

/**
 * @brief Allocates the emulator control GTK application object.
 *
 * Purpose: creates the Linux shell application used by `main`.
 *
 * @return Newly allocated `MyApplication` owned by the caller.
 *
 * @pre GTK type system must be initialized by normal application startup.
 * @post Returned application uses a non-unique application ID so multiple
 * emulator GUI instances can run during development.
 * @invariant Does not create the Flutter window until activation.
 */
MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
