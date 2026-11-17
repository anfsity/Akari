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
  gboolean monitor_signals_connected;
  gboolean multi_monitor_mode;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(FlView* view, MyApplication* self) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (self->multi_monitor_mode && GTK_WINDOW(toplevel) == self->primary_window &&
      self->primary_monitor == nullptr) {
    return;
  }
  gtk_widget_show(toplevel);
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

  const gchar* custom_title = g_getenv("AKARI_WINDOW_TITLE");
  gtk_window_set_title(
      window, (custom_title != nullptr && custom_title[0] != '\0')
                  ? custom_title
                  : "Akari Greeter");
  const gboolean is_windowed =
      g_strcmp0(g_getenv("AKARI_WINDOW_MODE"), "windowed") == 0;
  // Fullscreen greeter windows own the whole display without GTK client-side
  // headers; windowed previews and Theme Studio retain native OS decorations.
  gtk_window_set_decorated(window, is_windowed);
  if (monitor == nullptr) {
    gtk_window_set_default_size(window, 1280, 720);
  } else {
    fullscreen_on_monitor(window, monitor);
  }

  const gboolean is_primary = self->engine == nullptr;
  FlView* view;
  if (is_primary) {
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
  g_signal_connect_object(view, "first-frame", G_CALLBACK(first_frame_cb), self,
                          G_CONNECT_DEFAULT);
  if (self->multi_monitor_mode) {
    g_signal_connect_object(view, "focus-in-event", G_CALLBACK(focus_in_cb),
                            self, G_CONNECT_DEFAULT);
  }
  g_signal_connect_object(window, "delete-event", G_CALLBACK(close_window_cb),
                          self, G_CONNECT_DEFAULT);
  gtk_widget_realize(GTK_WIDGET(view));
  if (is_primary) {
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
    gtk_window_present(window);
    GtkWidget* child = gtk_bin_get_child(GTK_BIN(window));
    if (child != nullptr) {
      gtk_widget_grab_focus(child);
    }
  } else {
    window = create_window(self, monitor);
  }
  g_hash_table_insert(self->monitor_windows, g_object_ref(monitor), window);
}

static gboolean any_surviving_window_has_focus(MyApplication* self,
                                               GtkWindow* excluded) {
  GHashTableIter iterator;
  gpointer key, value;
  g_hash_table_iter_init(&iterator, self->monitor_windows);
  while (g_hash_table_iter_next(&iterator, &key, &value)) {
    GtkWindow* candidate = GTK_WINDOW(value);
    if (candidate != excluded && gtk_window_has_toplevel_focus(candidate)) {
      return TRUE;
    }
  }
  return FALSE;
}

static void monitor_removed_cb(GdkDisplay* display, GdkMonitor* monitor,
                               MyApplication* self) {
  GtkWindow* window =
      GTK_WINDOW(g_hash_table_lookup(self->monitor_windows, monitor));
  if (window == nullptr) {
    return;
  }
  g_debug("Removed greeter output; primary=%d, remaining=%d",
          window == self->primary_window, gdk_display_get_n_monitors(display));
  g_hash_table_remove(self->monitor_windows, monitor);
  GtkWindow* promoted_primary = nullptr;
  gboolean should_restore_focus = FALSE;
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
    should_restore_focus =
        !any_surviving_window_has_focus(self, secondary);
    if (secondary != nullptr) {
      gtk_widget_destroy(GTK_WIDGET(secondary));
    }
    self->primary_monitor = replacement;
    g_hash_table_insert(self->monitor_windows, g_object_ref(replacement),
                        window);
    promoted_primary = window;
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
  if (promoted_primary != nullptr && should_restore_focus) {
    gtk_window_present(promoted_primary);
    GtkWidget* child = gtk_bin_get_child(GTK_BIN(promoted_primary));
    if (child != nullptr) {
      gtk_widget_grab_focus(child);
    }
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

  self->multi_monitor_mode = TRUE;
  GdkDisplay* display = gdk_display_get_default();
  if (!self->monitor_signals_connected) {
    self->monitor_signals_connected = TRUE;
    g_signal_connect_object(display, "monitor-added",
                            G_CALLBACK(monitor_added_cb), self,
                            G_CONNECT_DEFAULT);
    g_signal_connect_object(display, "monitor-removed",
                            G_CALLBACK(monitor_removed_cb), self,
                            G_CONNECT_DEFAULT);
  }
  const int monitor_count = gdk_display_get_n_monitors(display);
  if (monitor_count == 0) {
    // Park an unshown primary window so GApplication stays alive and starts
    // the Dart engine while waiting for the first monitor hotplug event.
    gtk_widget_hide(GTK_WIDGET(create_window(self, nullptr)));
    return;
  }
  for (int index = 0; index < monitor_count; index++) {
    monitor_added_cb(display, gdk_display_get_monitor(display, index), self);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments =
      (*arguments != nullptr && (*arguments)[0] != nullptr)
          ? g_strdupv(*arguments + 1)
          : g_new0(gchar*, 1);

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

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->monitor_windows, g_hash_table_unref);
  self->primary_window = nullptr;
  self->primary_monitor = nullptr;
  g_clear_object(&self->display_channel);
  g_clear_object(&self->engine);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
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
