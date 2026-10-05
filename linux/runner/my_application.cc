#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlEngine* engine;
  FlMethodChannel* display_channel;
  GHashTable* monitor_windows;
  GtkWindow* primary_window;
  GdkMonitor* primary_monitor;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(FlView* view, gpointer user_data) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static gboolean focus_in_cb(FlView* view, GdkEventFocus* event,
                            MyApplication* self) {
  g_debug("Greeter focus on view %" G_GINT64_FORMAT, fl_view_get_id(view));
  g_autoptr(FlValue) view_id = fl_value_new_int(fl_view_get_id(view));
  fl_method_channel_invoke_method(self->display_channel, "focusView", view_id,
                                  nullptr, nullptr, nullptr);
  return FALSE;
}

static gboolean close_window_cb(GtkWidget* window, GdkEvent* event,
                                MyApplication* self) {
  g_application_quit(G_APPLICATION(self));
  return TRUE;
}

static void fullscreen_on_monitor(GtkWindow* window, GdkMonitor* monitor) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  const int count = gdk_display_get_n_monitors(display);
  for (int index = 0; index < count; index++) {
    if (gdk_display_get_monitor(display, index) == monitor) {
      gtk_window_fullscreen_on_monitor(
          window, gdk_display_get_default_screen(display), index);
      return;
    }
  }
}

// All windows share one engine and Dart feature. Starting one engine per output
// would create competing D-Bus clients and independent authentication attempts.
static GtkWindow* create_window(MyApplication* self, GdkMonitor* monitor) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));

  gtk_window_set_title(window, "Akari Greeter");
  // The greeter owns the whole display; compositor border rules cannot remove
  // a GTK client-side header. Windowed previews use the desktop's own scale.
  gtk_window_set_decorated(window, FALSE);
  if (monitor == nullptr) {
    gtk_window_set_default_size(window, 1280, 720);
  } else {
    fullscreen_on_monitor(window, monitor);
  }

  FlView* view;
  if (self->engine == nullptr) {
    g_autoptr(FlDartProject) project = fl_dart_project_new();
    fl_dart_project_set_dart_entrypoint_arguments(
        project, self->dart_entrypoint_arguments);
    view = fl_view_new(project);
    self->engine = FL_ENGINE(g_object_ref(fl_view_get_engine(view)));
    self->primary_window = window;
    self->primary_monitor = monitor;
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    self->display_channel =
        fl_method_channel_new(fl_engine_get_binary_messenger(self->engine),
                              "akari/displays", FL_METHOD_CODEC(codec));
  } else {
    view = fl_view_new_for_engine(self->engine);
  }

  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect(view, "first-frame", G_CALLBACK(first_frame_cb), nullptr);
  if (monitor != nullptr) {
    g_signal_connect(view, "focus-in-event", G_CALLBACK(focus_in_cb), self);
  }
  g_signal_connect(window, "delete-event", G_CALLBACK(close_window_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));
  if (window == self->primary_window) {
    fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  }

  gtk_widget_grab_focus(GTK_WIDGET(view));
  if (monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    g_debug("Created greeter view %" G_GINT64_FORMAT " on output at %d,%d",
            fl_view_get_id(view), geometry.x, geometry.y);
  }
  return window;
}

static void monitor_added_cb(GdkDisplay* display, GdkMonitor* monitor,
                             MyApplication* self) {
  GtkWindow* window;
  if (self->primary_window != nullptr && self->primary_monitor == nullptr) {
    window = self->primary_window;
    self->primary_monitor = monitor;
    fullscreen_on_monitor(window, monitor);
    gtk_widget_show(GTK_WIDGET(window));
  } else {
    window = create_window(self, monitor);
  }
  g_hash_table_insert(self->monitor_windows, g_object_ref(monitor), window);
}

static void monitor_removed_cb(GdkDisplay* display, GdkMonitor* monitor,
                               MyApplication* self) {
  GtkWindow* window =
      GTK_WINDOW(g_hash_table_lookup(self->monitor_windows, monitor));
  g_debug("Removed greeter output; primary=%d, remaining=%d",
          window == self->primary_window, gdk_display_get_n_monitors(display));
  g_hash_table_remove(self->monitor_windows, monitor);
  if (window == self->primary_window) {
    // Keep the implicit view alive: it owns the app root and engine lifecycle.
    // Replace a surviving output's secondary window with this primary window.
    // With no outputs, park it until a monitor reconnects.
    self->primary_monitor = nullptr;
    if (gdk_display_get_n_monitors(display) == 0) {
      gtk_widget_hide(GTK_WIDGET(window));
      return;
    }
    GdkMonitor* replacement = gdk_display_get_monitor(display, 0);
    GtkWindow* secondary =
        GTK_WINDOW(g_hash_table_lookup(self->monitor_windows, replacement));
    if (secondary != nullptr) {
      gtk_widget_destroy(GTK_WIDGET(secondary));
    }
    self->primary_monitor = replacement;
    g_hash_table_insert(self->monitor_windows, g_object_ref(replacement),
                        window);
  } else {
    gtk_widget_destroy(GTK_WIDGET(window));
  }

  // GTK takes monitor indices; removing an output can renumber surviving ones.
  GHashTableIter iterator;
  gpointer key, value;
  g_hash_table_iter_init(&iterator, self->monitor_windows);
  while (g_hash_table_iter_next(&iterator, &key, &value)) {
    fullscreen_on_monitor(GTK_WINDOW(value), GDK_MONITOR(key));
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->primary_window != nullptr) {
    gtk_window_present(self->primary_window);
    return;
  }
  if (g_strcmp0(g_getenv("AKARI_WINDOW_MODE"), "windowed") == 0) {
    create_window(self, nullptr);
    return;
  }
  if (g_strcmp0(g_getenv("AKARI_DISPLAY_MODE"), "single") == 0) {
    gtk_window_fullscreen(create_window(self, nullptr));
    return;
  }

  GdkDisplay* display = gdk_display_get_default();
  g_signal_connect_object(display, "monitor-added",
                          G_CALLBACK(monitor_added_cb), self,
                          G_CONNECT_DEFAULT);
  g_signal_connect_object(display, "monitor-removed",
                          G_CALLBACK(monitor_removed_cb), self,
                          G_CONNECT_DEFAULT);
  for (int index = 0; index < gdk_display_get_n_monitors(display); index++) {
    monitor_added_cb(display, gdk_display_get_monitor(display, index), self);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
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

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->monitor_windows, g_hash_table_unref);
  g_clear_object(&self->display_channel);
  g_clear_object(&self->engine);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->monitor_windows = g_hash_table_new_full(g_direct_hash, g_direct_equal,
                                                g_object_unref, nullptr);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
