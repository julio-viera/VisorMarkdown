#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  FlMethodChannel* file_channel;
  GQueue* pending_requests;
  gboolean dart_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Only use transparent corners when GDK reports compositing and an RGBA visual.
static void appearance_method_cb(FlMethodChannel* channel,
                                 FlMethodCall* call,
                                 gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(call), "supportsRoundedCorners") == 0) {
    g_autoptr(FlValue) supported = fl_value_new_bool(GPOINTER_TO_INT(user_data));
    fl_method_call_respond_success(call, supported, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

// Requests are queued until Dart installs its handler, including cold starts.
static void desktop_files_method_cb(FlMethodChannel* channel,
                                    FlMethodCall* call,
                                    gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(call), "getInitialRequests") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  g_autoptr(FlValue) requests = fl_value_new_list();
  while (!g_queue_is_empty(self->pending_requests)) {
    fl_value_append_take(requests,
        static_cast<FlValue*>(g_queue_pop_head(self->pending_requests)));
  }
  self->dart_ready = TRUE;
  fl_method_call_respond_success(call, requests, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  GdkScreen* appearance_screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(appearance_screen);
  const gboolean rounded_corners =
      rgba_visual != nullptr && gdk_screen_is_composited(appearance_screen);
  if (rounded_corners) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  }

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
    gtk_header_bar_set_title(header_bar, "Visor Markdown");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Visor Markdown");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color,
                 rounded_corners ? "rgba(0,0,0,0)" : "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_autoptr(FlStandardMethodCodec) appearance_codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) appearance_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.github.julio_viera.VisorMarkdown/window_appearance",
      FL_METHOD_CODEC(appearance_codec));
  fl_method_channel_set_method_call_handler(appearance_channel,
      appearance_method_cb, GINT_TO_POINTER(rounded_corners), nullptr);
  g_object_set_data_full(G_OBJECT(view), "visor-markdown-appearance-channel",
                        g_steal_pointer(&appearance_channel), g_object_unref);

  self->file_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.github.julio_viera.VisorMarkdown/desktop_file_open",
      FL_METHOD_CODEC(appearance_codec));
  fl_method_channel_set_method_call_handler(self->file_channel,
      desktop_files_method_cb, self, nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// GApplication forwards subsequent invocations over the user's session bus.
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  int argc = 0;
  g_auto(GStrv) arguments = g_application_command_line_get_arguments(command_line, &argc);
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (int i = 1; i < argc; ++i) {
    if (g_strcmp0(arguments[i], "--") == 0) continue;
    g_autoptr(GFile) file = g_application_command_line_create_file_for_arg(command_line, arguments[i]);
    g_autofree gchar* path = g_file_get_path(file);
    if (path == nullptr) {
      g_application_command_line_printerr(command_line, "Only local files are supported: %s\n", arguments[i]);
      return 1;
    }
    fl_value_append_take(paths, fl_value_new_string(path));
  }
  g_autoptr(FlValue) request = fl_value_new_map();
  fl_value_set_string(request, "paths", paths);
  // Queue before creating the window; both startup and live opens use one path.
  if (self->dart_ready && self->file_channel != nullptr) {
    fl_method_channel_invoke_method(self->file_channel, "openRequest", request,
                                   nullptr, nullptr, nullptr);
  } else {
    g_queue_push_tail(self->pending_requests, fl_value_ref(request));
  }
  g_application_activate(application);
  return 0;
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
  g_clear_object(&self->file_channel);
  if (self->pending_requests != nullptr) {
    g_queue_free_full(self->pending_requests, reinterpret_cast<GDestroyNotify>(fl_value_unref));
    self->pending_requests = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_requests = g_queue_new();
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
}
