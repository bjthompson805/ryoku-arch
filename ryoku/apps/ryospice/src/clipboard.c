#include "clipboard.h"

#include <spice/vd_agent.h>
#include <string.h>

/* v1: text only. Both CLIPBOARD and PRIMARY selections are wired the same
 * way, distinguished only by which GdkClipboard object we watch/write and
 * the VD_AGENT_CLIPBOARD_SELECTION_* id we tag messages with. */

#define SELECTION_COUNT 2 /* VD_AGENT_CLIPBOARD_SELECTION_{CLIPBOARD,PRIMARY} */

typedef struct {
	GtkWidget *view;      /* borrowed; app-lifetime, same as input.c's ctx */
	SpiceMainChannel *channel; /* borrowed; NULL until the channel opens */
	gboolean applying_from_guest[SELECTION_COUNT]; /* guard against our own
	                                * gdk_clipboard_set() re-triggering a
	                                * grab back to the guest */
} ClipboardCtx;

typedef struct {
	ClipboardCtx *ctx;
	guint selection;
} SelectionCtx;

static GdkClipboard *clipboard_for_selection(ClipboardCtx *ctx, guint selection) {
	return selection == VD_AGENT_CLIPBOARD_SELECTION_PRIMARY
	           ? gtk_widget_get_primary_clipboard(ctx->view)
	           : gtk_widget_get_clipboard(ctx->view);
}

static void on_clipboard_changed(GdkClipboard *clipboard, gpointer user_data) {
	SelectionCtx *sctx = user_data;
	ClipboardCtx *ctx = sctx->ctx;
	(void)clipboard;
	if (!ctx->channel || ctx->applying_from_guest[sctx->selection]) {
		return;
	}
	/* We only advertise text for now; a real content check (formats)
	 * would let us skip announcing when the clipboard holds something
	 * else, but grabbing unconditionally is harmless -- the guest just
	 * won't get useful data back if it requests a type we can't serve. */
	guint32 types[] = {VD_AGENT_CLIPBOARD_UTF8_TEXT};
	spice_main_channel_clipboard_selection_grab(ctx->channel, sctx->selection, types,
	                                             G_N_ELEMENTS(types));
}

static void on_text_ready_for_guest(GObject *source, GAsyncResult *result, gpointer user_data) {
	SelectionCtx *sctx = user_data;
	ClipboardCtx *ctx = sctx->ctx;
	guint selection = sctx->selection;
	g_free(sctx);

	GError *error = NULL;
	char *text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(source), result, &error);
	if (!text) {
		g_warning("ryospice: clipboard read for guest failed: %s", error ? error->message : "?");
		g_clear_error(&error);
		return;
	}
	if (ctx->channel) {
		spice_main_channel_clipboard_selection_notify(ctx->channel, selection,
		                                               VD_AGENT_CLIPBOARD_UTF8_TEXT,
		                                               (const guchar *)text, strlen(text));
	}
	g_free(text);
}

/* Guest has data available and told us which types -- text is all we
 * handle, so only accept if it offered VD_AGENT_CLIPBOARD_UTF8_TEXT. */
static gboolean on_selection_grab(SpiceMainChannel *channel, guint selection, gpointer types,
                                   guint ntypes, gpointer user_data) {
	(void)user_data;
	if (selection >= SELECTION_COUNT) {
		return FALSE;
	}
	const guint32 *type_list = types;
	for (guint i = 0; i < ntypes; i++) {
		if (type_list[i] == VD_AGENT_CLIPBOARD_UTF8_TEXT) {
			/* Fetch it now so it's ready by the time something on the
			 * host actually tries to paste. */
			spice_main_channel_clipboard_selection_request(channel, selection,
			                                                VD_AGENT_CLIPBOARD_UTF8_TEXT);
			return TRUE;
		}
	}
	return FALSE;
}

/* Guest sent us the data we asked for (paste guest -> host direction). */
static void on_selection_data(SpiceMainChannel *channel, guint selection, guint type, gpointer data,
                               guint size, gpointer user_data) {
	(void)channel;
	ClipboardCtx *ctx = user_data;
	if (selection >= SELECTION_COUNT || type != VD_AGENT_CLIPBOARD_UTF8_TEXT) {
		return;
	}
	char *text = g_strndup((const char *)data, size);
	GdkClipboard *clipboard = clipboard_for_selection(ctx, selection);
	ctx->applying_from_guest[selection] = TRUE;
	gdk_clipboard_set_text(clipboard, text);
	ctx->applying_from_guest[selection] = FALSE;
	g_free(text);
}

/* Guest wants OUR data (paste host -> guest direction): read it
 * asynchronously and notify once it's ready. */
static gboolean on_selection_request(SpiceMainChannel *channel, guint selection, guint type,
                                      gpointer user_data) {
	ClipboardCtx *ctx = user_data;
	if (selection >= SELECTION_COUNT || type != VD_AGENT_CLIPBOARD_UTF8_TEXT) {
		return FALSE;
	}
	(void)channel;
	GdkClipboard *clipboard = clipboard_for_selection(ctx, selection);
	SelectionCtx *sctx = g_new(SelectionCtx, 1);
	sctx->ctx = ctx;
	sctx->selection = selection;
	gdk_clipboard_read_text_async(clipboard, NULL, on_text_ready_for_guest, sctx);
	return TRUE;
}

static void on_channel_new(SpiceSession *session, SpiceChannel *channel, gpointer user_data) {
	(void)session;
	ClipboardCtx *ctx = user_data;
	if (!SPICE_IS_MAIN_CHANNEL(channel)) {
		return;
	}
	ctx->channel = SPICE_MAIN_CHANNEL(channel);
	g_signal_connect(channel, "main-clipboard-selection-grab", G_CALLBACK(on_selection_grab), ctx);
	g_signal_connect(channel, "main-clipboard-selection", G_CALLBACK(on_selection_data), ctx);
	g_signal_connect(channel, "main-clipboard-selection-request", G_CALLBACK(on_selection_request), ctx);
	/* main channel's own connect is already handled in main.c */
}

void ryo_spice_clipboard_attach(GtkWidget *view, SpiceSession *session) {
	ClipboardCtx *ctx = g_new0(ClipboardCtx, 1);
	ctx->view = view;

	g_signal_connect(session, "channel-new", G_CALLBACK(on_channel_new), ctx);

	for (guint selection = 0; selection < SELECTION_COUNT; selection++) {
		SelectionCtx *sctx = g_new(SelectionCtx, 1);
		sctx->ctx = ctx;
		sctx->selection = selection;
		GdkClipboard *clipboard = clipboard_for_selection(ctx, selection);
		g_signal_connect_data(clipboard, "changed", G_CALLBACK(on_clipboard_changed), sctx,
		                       (GClosureNotify)g_free, 0);
	}
}
