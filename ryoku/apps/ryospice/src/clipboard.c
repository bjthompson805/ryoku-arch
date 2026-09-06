#include "clipboard.h"

#include <spice/vd_agent.h>
#include <string.h>

/* Both CLIPBOARD and PRIMARY selections are wired the same way, distinguished
 * only by which GdkClipboard object we watch/write and the
 * VD_AGENT_CLIPBOARD_SELECTION_* id we tag messages with. Text and image
 * formats (PNG/BMP/TIFF/JPG) share the same generic mime-type <-> spice-type
 * mapping -- see type2mime below, kept in sync with vdagent's own copy of
 * this table in the paired spice-vdagent-wayland fork.
 *
 * Host -> guest (host copied something, guest should see it) is lazy: we
 * only fetch the host clipboard's actual bytes once the guest asks for a
 * specific type, via a GdkContentProvider (RyoSpiceClipboardProvider below)
 * whose write_mime_type_async requests exactly that type over the SPICE
 * channel. This mirrors the paired vdagent-side design and avoids fetching
 * (or over the wire, sending) formats nothing on either end ever reads.
 */

#define SELECTION_COUNT 2 /* VD_AGENT_CLIPBOARD_SELECTION_{CLIPBOARD,PRIMARY} */
#define TYPE_COUNT (VD_AGENT_CLIPBOARD_IMAGE_JPG + 1)

static const struct {
	guint type;
	const char *mime_type;
} type2mime[] = {
	{VD_AGENT_CLIPBOARD_UTF8_TEXT,  "text/plain;charset=utf-8"},
	{VD_AGENT_CLIPBOARD_IMAGE_PNG,  "image/png"},
	{VD_AGENT_CLIPBOARD_IMAGE_BMP,  "image/bmp"},
	{VD_AGENT_CLIPBOARD_IMAGE_TIFF, "image/tiff"},
	{VD_AGENT_CLIPBOARD_IMAGE_JPG,  "image/jpeg"},
};

static guint type_from_mime_type(const char *mime_type) {
	for (guint i = 0; i < G_N_ELEMENTS(type2mime); i++) {
		if (g_ascii_strcasecmp(mime_type, type2mime[i].mime_type) == 0) {
			return type2mime[i].type;
		}
	}
	return VD_AGENT_CLIPBOARD_NONE;
}

static const char *mime_type_for_type(guint type) {
	for (guint i = 0; i < G_N_ELEMENTS(type2mime); i++) {
		if (type2mime[i].type == type) {
			return type2mime[i].mime_type;
		}
	}
	return NULL;
}

typedef struct {
	GtkWidget *view;      /* borrowed; app-lifetime, same as input.c's ctx */
	SpiceMainChannel *channel; /* borrowed; NULL until the channel opens */
	gboolean applying_from_guest[SELECTION_COUNT]; /* guard against our own
	                                * gdk_clipboard_set_content() re-triggering
	                                * a grab back to the guest */
	/* types the guest most recently told us (via selection-grab) it can
	 * supply for this selection; read by the content provider's
	 * ref_formats/write_mime_type_async below. */
	gboolean type_available[SELECTION_COUNT][TYPE_COUNT];
	GList *requests_from_apps[SELECTION_COUNT]; /* GTask* list: host app --> guest */
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

/* ---- content provider: host apps read guest clipboard data through this ---- */

#define RYO_TYPE_CLIPBOARD_PROVIDER (ryo_spice_clipboard_provider_get_type())
G_DECLARE_FINAL_TYPE(RyoSpiceClipboardProvider, ryo_spice_clipboard_provider,
                      RYO_SPICE, CLIPBOARD_PROVIDER, GdkContentProvider)

struct _RyoSpiceClipboardProvider {
	GdkContentProvider parent;
	ClipboardCtx *ctx; /* borrowed; outlives every provider it creates */
	guint selection;
};

G_DEFINE_FINAL_TYPE(RyoSpiceClipboardProvider, ryo_spice_clipboard_provider, GDK_TYPE_CONTENT_PROVIDER)

static GdkContentFormats *provider_ref_formats(GdkContentProvider *provider) {
	RyoSpiceClipboardProvider *self = RYO_SPICE_CLIPBOARD_PROVIDER(provider);
	GdkContentFormatsBuilder *builder = gdk_content_formats_builder_new();
	for (guint type = 0; type < TYPE_COUNT; type++) {
		if (self->ctx->type_available[self->selection][type]) {
			gdk_content_formats_builder_add_mime_type(builder, mime_type_for_type(type));
		}
	}
	return gdk_content_formats_builder_free_to_formats(builder);
}

static void provider_write_mime_type_async(GdkContentProvider *provider, const char *mime_type,
                                            GOutputStream *stream, int io_priority,
                                            GCancellable *cancellable, GAsyncReadyCallback callback,
                                            gpointer user_data) {
	(void)io_priority;
	RyoSpiceClipboardProvider *self = RYO_SPICE_CLIPBOARD_PROVIDER(provider);
	ClipboardCtx *ctx = self->ctx;
	guint selection = self->selection;

	GTask *task = g_task_new(provider, cancellable, callback, user_data);

	guint type = type_from_mime_type(mime_type);
	if (type == VD_AGENT_CLIPBOARD_NONE || !ctx->type_available[selection][type] || !ctx->channel) {
		g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
		                         "unsupported mime type %s", mime_type);
		g_object_unref(task);
		return;
	}

	g_task_set_task_data(task, g_object_ref(stream), g_object_unref);
	g_object_set_data(G_OBJECT(task), "ryospice-type", GUINT_TO_POINTER(type));
	ctx->requests_from_apps[selection] = g_list_append(ctx->requests_from_apps[selection], task);

	spice_main_channel_clipboard_selection_request(ctx->channel, selection, type);
}

static gboolean provider_write_mime_type_finish(GdkContentProvider *provider, GAsyncResult *result,
                                                 GError **error) {
	(void)provider;
	return g_task_propagate_boolean(G_TASK(result), error);
}

static void ryo_spice_clipboard_provider_class_init(RyoSpiceClipboardProviderClass *klass) {
	GdkContentProviderClass *provider_class = GDK_CONTENT_PROVIDER_CLASS(klass);
	provider_class->ref_formats = provider_ref_formats;
	provider_class->write_mime_type_async = provider_write_mime_type_async;
	provider_class->write_mime_type_finish = provider_write_mime_type_finish;
}

static void ryo_spice_clipboard_provider_init(RyoSpiceClipboardProvider *self) {
	(void)self;
}

/* ---- host clipboard changed -> tell the guest what we can offer ---- */

static void on_clipboard_changed(GdkClipboard *clipboard, gpointer user_data) {
	SelectionCtx *sctx = user_data;
	ClipboardCtx *ctx = sctx->ctx;
	guint selection = sctx->selection;
	if (!ctx->channel || ctx->applying_from_guest[selection]) {
		return;
	}

	GdkContentFormats *formats = gdk_clipboard_get_formats(clipboard);
	guint32 types[TYPE_COUNT];
	guint n_types = 0;
	/* start at 1: slot 0 is VD_AGENT_CLIPBOARD_NONE, which has no mime
	 * entry in type2mime (mime_type_for_type(0) is NULL). */
	for (guint type = 1; type < TYPE_COUNT; type++) {
		if (gdk_content_formats_contain_mime_type(formats, mime_type_for_type(type))) {
			types[n_types++] = type;
		}
	}
	if (n_types == 0) {
		return; /* nothing on the host clipboard we know how to offer */
	}
	spice_main_channel_clipboard_selection_grab(ctx->channel, selection, types, n_types);
}

/* ---- guest sent us data we requested (paste guest -> host direction) ---- */

static void on_selection_data(SpiceMainChannel *channel, guint selection, guint type, gpointer data,
                               guint size, gpointer user_data) {
	(void)channel;
	ClipboardCtx *ctx = user_data;
	if (selection >= SELECTION_COUNT || type >= TYPE_COUNT) {
		return;
	}

	/* Match by the type each request is actually waiting on, not queue
	 * position -- more than one host app can be probing formats at once. */
	GList *l;
	for (l = ctx->requests_from_apps[selection]; l != NULL; l = l->next) {
		guint expected = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(l->data), "ryospice-type"));
		if (expected == type) {
			break;
		}
	}
	if (l == NULL) {
		g_warning("ryospice: sel=%u: no pending request for type=%u, skipping", selection, type);
		return;
	}
	GTask *task = l->data;
	ctx->requests_from_apps[selection] = g_list_delete_link(ctx->requests_from_apps[selection], l);

	GOutputStream *stream = g_task_get_task_data(task);
	GError *error = NULL;
	if (g_output_stream_write_all(stream, data, size, NULL, g_task_get_cancellable(task), &error)) {
		g_task_return_boolean(task, TRUE);
	} else {
		g_task_return_error(task, error);
	}
	g_object_unref(task);
}

/* Guest has data available and told us which types -- record them and hand
 * a lazy content provider to the host clipboard; nothing is actually
 * fetched from the guest until a host app asks for a specific format. */
static gboolean on_selection_grab(SpiceMainChannel *channel, guint selection, gpointer types,
                                   guint ntypes, gpointer user_data) {
	ClipboardCtx *ctx = user_data;
	if (selection >= SELECTION_COUNT) {
		return FALSE;
	}

	const guint32 *type_list = types;
	guint n_supported = 0;
	for (guint type = 0; type < TYPE_COUNT; type++) {
		ctx->type_available[selection][type] = FALSE;
	}
	for (guint i = 0; i < ntypes; i++) {
		if (type_list[i] < TYPE_COUNT && mime_type_for_type(type_list[i])) {
			ctx->type_available[selection][type_list[i]] = TRUE;
			n_supported++;
		}
	}
	if (n_supported == 0) {
		return FALSE;
	}

	RyoSpiceClipboardProvider *provider = g_object_new(RYO_TYPE_CLIPBOARD_PROVIDER, NULL);
	provider->ctx = ctx;
	provider->selection = selection;

	GdkClipboard *clipboard = clipboard_for_selection(ctx, selection);
	ctx->applying_from_guest[selection] = TRUE;
	gdk_clipboard_set_content(clipboard, GDK_CONTENT_PROVIDER(provider));
	ctx->applying_from_guest[selection] = FALSE;
	g_object_unref(provider);
	return TRUE;
}

/* ---- guest wants OUR data (paste host -> guest direction) ---- */

typedef struct {
	ClipboardCtx *ctx;
	guint selection;
	guint type;
} ReadRequest;

static void on_splice_ready(GObject *source, GAsyncResult *result, gpointer user_data) {
	ReadRequest *req = user_data;
	GOutputStream *sink = G_OUTPUT_STREAM(source);
	GError *error = NULL;

	gssize spliced = g_output_stream_splice_finish(sink, result, &error);
	if (spliced < 0) {
		g_warning("ryospice: clipboard read for guest failed: %s", error ? error->message : "?");
		g_clear_error(&error);
		g_object_unref(sink);
		g_free(req);
		return;
	}

	gpointer data = g_memory_output_stream_get_data(G_MEMORY_OUTPUT_STREAM(sink));
	gsize size = g_memory_output_stream_get_data_size(G_MEMORY_OUTPUT_STREAM(sink));
	if (req->ctx->channel) {
		spice_main_channel_clipboard_selection_notify(req->ctx->channel, req->selection, req->type,
		                                               data, size);
	}
	g_object_unref(sink);
	g_free(req);
}

static void on_clipboard_read_ready(GObject *source, GAsyncResult *result, gpointer user_data) {
	ReadRequest *req = user_data;
	GError *error = NULL;
	GInputStream *stream = gdk_clipboard_read_finish(GDK_CLIPBOARD(source), result, NULL, &error);
	if (!stream) {
		g_warning("ryospice: clipboard read for guest failed: %s", error ? error->message : "?");
		g_clear_error(&error);
		if (req->ctx->channel) {
			spice_main_channel_clipboard_selection_notify(req->ctx->channel, req->selection, req->type,
			                                               NULL, 0);
		}
		g_free(req);
		return;
	}

	GOutputStream *sink = g_memory_output_stream_new_resizable();
	g_output_stream_splice_async(sink, stream, G_OUTPUT_STREAM_SPLICE_CLOSE_SOURCE,
	                              G_PRIORITY_DEFAULT, NULL, on_splice_ready, req);
	g_object_unref(stream);
}

static gboolean on_selection_request(SpiceMainChannel *channel, guint selection, guint type,
                                      gpointer user_data) {
	ClipboardCtx *ctx = user_data;
	if (selection >= SELECTION_COUNT || type >= TYPE_COUNT || !mime_type_for_type(type)) {
		return FALSE;
	}
	(void)channel;

	GdkClipboard *clipboard = clipboard_for_selection(ctx, selection);
	ReadRequest *req = g_new(ReadRequest, 1);
	req->ctx = ctx;
	req->selection = selection;
	req->type = type;

	const char *mime_types[] = {mime_type_for_type(type), NULL};
	gdk_clipboard_read_async(clipboard, mime_types, G_PRIORITY_DEFAULT, NULL,
	                          on_clipboard_read_ready, req);
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
