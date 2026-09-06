/* ryospice: a minimal GTK4 SPICE viewer for ryovm's Linux-guest VMs.
 *
 * Exists to remove the one performance ceiling the server-side zero-copy
 * fix (bin/qemu-gl-wrapper) couldn't touch: spicy/remote-viewer are built
 * on spice-client-gtk-3.0, whose GtkGLArea has no Wayland surface of its
 * own and must CPU-readback each GL frame into a Cairo surface to show it.
 * GTK4 dropped that readback (gtk_gl_area_snapshot uses
 * gtk_snapshot_append_texture, a GPU texture, not Cairo) -- see display.c
 * and the ryospice plan doc for the full trace.
 *
 * CLI shape intentionally mirrors spicy's, so ryovm's bin/ryovm only needs
 * a one-line addition per call site, not a rewrite:
 *   ryospice --title <name> --uri=spice+unix://<path>
 *   ryospice --title <name> --port <port>
 */
#include <gtk/gtk.h>
#include <spice-client.h>
#include <stdlib.h>
#include <string.h>

#include "clipboard.h"
#include "display.h"
#include "input.h"

typedef struct {
	char *title;
	char *uri; /* owned, g_free */
} Args;

static gboolean parse_args(int argc, char **argv, Args *out, GError **error) {
	out->title = NULL;
	out->uri = NULL;

	for (int i = 1; i < argc; i++) {
		const char *arg = argv[i];
		if (g_str_has_prefix(arg, "--uri=")) {
			out->uri = g_strdup(arg + strlen("--uri="));
		} else if (g_strcmp0(arg, "--title") == 0 && i + 1 < argc) {
			out->title = g_strdup(argv[++i]);
		} else if (g_strcmp0(arg, "--port") == 0 && i + 1 < argc) {
			out->uri = g_strdup_printf("spice://localhost:%s", argv[++i]);
		} else {
			g_set_error(error, G_OPTION_ERROR, G_OPTION_ERROR_UNKNOWN_OPTION,
			            "unrecognised argument: %s", arg);
			return FALSE;
		}
	}

	if (!out->uri) {
		g_set_error(error, G_OPTION_ERROR, G_OPTION_ERROR_FAILED,
		            "usage: ryospice --title <name> (--uri=spice+unix://<path> | --port <port>)");
		return FALSE;
	}
	return TRUE;
}

static void on_session_channel_new(SpiceSession *session, SpiceChannel *channel,
                                    gpointer user_data) {
	(void)user_data;
	if (SPICE_IS_MAIN_CHANNEL(channel)) {
		spice_channel_connect(channel);
	}
}

static void on_activate(GtkApplication *app, gpointer user_data) {
	Args *args = user_data;

	GtkWidget *window = gtk_application_window_new(app);
	gtk_window_set_title(GTK_WINDOW(window), args->title ? args->title : "ryospice");
	gtk_window_set_default_size(GTK_WINDOW(window), 1280, 800);

	GtkWidget *view = ryo_spice_view_new();
	gtk_window_set_child(GTK_WINDOW(window), view);

	SpiceSession *session = spice_session_new();
	g_object_set(session, "uri", args->uri, NULL);

	/* Main channel needs its own connect call the moment it appears, same
	 * as the display channel does in display.c -- SpiceSession only
	 * hands out channels via "channel-new", it doesn't connect them. */
	g_signal_connect(session, "channel-new", G_CALLBACK(on_session_channel_new), NULL);

	ryo_spice_view_attach_session(RYO_SPICE_VIEW(view), session);
	ryo_spice_input_attach(RYO_SPICE_VIEW(view), session);
	ryo_spice_clipboard_attach(view, session);

	if (!spice_session_connect(session)) {
		g_printerr("ryospice: failed to connect to %s\n", args->uri);
		g_application_quit(G_APPLICATION(app));
		return;
	}

	gtk_window_present(GTK_WINDOW(window));
}

int main(int argc, char **argv) {
	Args args = {0};
	GError *error = NULL;
	if (!parse_args(argc, argv, &args, &error)) {
		g_printerr("ryospice: %s\n", error->message);
		g_error_free(error);
		return 1;
	}

	GtkApplication *app = gtk_application_new("org.ryoku.ryospice", G_APPLICATION_DEFAULT_FLAGS);
	g_signal_connect(app, "activate", G_CALLBACK(on_activate), &args);
	int status = g_application_run(G_APPLICATION(app), 0, NULL);

	g_object_unref(app);
	g_free(args.title);
	g_free(args.uri);
	return status;
}
