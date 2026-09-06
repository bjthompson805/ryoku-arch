#include "display.h"

#include <drm_fourcc.h>
#include <errno.h>
#include <unistd.h>

/* Everything here exists to avoid the one thing spice-gtk's GTK3 widget
 * cannot avoid: GtkGLArea has no Wayland surface of its own (it's
 * GDK_INPUT_ONLY), so GTK3 must read each GL-rendered frame back into a
 * Cairo image surface (gdk_cairo_draw_from_gl) to composite it into the
 * window. That CPU-side readback is the whole reason this file exists.
 *
 * GTK4's GdkDmabufTextureBuilder imports the SPICE-provided DMA-BUF fd
 * directly into a GdkTexture that GSK composites on the GPU -- no readback,
 * no manual EGL context needed here at all. See the ryospice plan doc for
 * the full trace (GTK3 vs GTK4 gtkglarea.c, GtkGLArea's GDK_INPUT_ONLY
 * window, etc.) that led here.
 */

struct _RyoSpiceView {
	GtkWidget parent_instance;
	SpiceDisplayChannel *channel; /* borrowed; owned by the session */
	GdkTexture *texture;
	gboolean y0top;
};

G_DEFINE_FINAL_TYPE(RyoSpiceView, ryo_spice_view, GTK_TYPE_WIDGET)

static void ryo_spice_view_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	RyoSpiceView *self = RYO_SPICE_VIEW(widget);
	int width = gtk_widget_get_width(widget);
	int height = gtk_widget_get_height(widget);

	if (!self->texture || width <= 0 || height <= 0) {
		return;
	}

	int tex_w = gdk_texture_get_width(self->texture);
	int tex_h = gdk_texture_get_height(self->texture);
	if (tex_w <= 0 || tex_h <= 0) {
		return;
	}

	/* Fill the widget, ignoring aspect ratio for now (v1 -- ryovm always
	 * sizes the guest resolution to match the window it's shown in, so
	 * this hasn't mattered in practice yet). */
	gtk_snapshot_save(snapshot);
	if (self->y0top) {
		gtk_snapshot_translate(snapshot, &GRAPHENE_POINT_INIT(0, height));
		gtk_snapshot_scale(snapshot, (float)width / tex_w, -(float)height / tex_h);
	} else {
		gtk_snapshot_scale(snapshot, (float)width / tex_w, (float)height / tex_h);
	}
	gtk_snapshot_append_texture(snapshot, self->texture,
	                             &GRAPHENE_RECT_INIT(0, 0, tex_w, tex_h));
	gtk_snapshot_restore(snapshot);
}

static void ryo_spice_view_measure(GtkWidget *widget, GtkOrientation orientation,
                                    int for_size, int *minimum, int *natural,
                                    int *minimum_baseline, int *natural_baseline) {
	RyoSpiceView *self = RYO_SPICE_VIEW(widget);
	int w = self->texture ? gdk_texture_get_width(self->texture) : 1280;
	int h = self->texture ? gdk_texture_get_height(self->texture) : 800;
	*minimum = *natural = (orientation == GTK_ORIENTATION_HORIZONTAL) ? w : h;
	*minimum_baseline = *natural_baseline = -1;
	(void)for_size;
}

static void ryo_spice_view_dispose(GObject *object) {
	RyoSpiceView *self = RYO_SPICE_VIEW(object);
	g_clear_object(&self->texture);
	G_OBJECT_CLASS(ryo_spice_view_parent_class)->dispose(object);
}

static void ryo_spice_view_class_init(RyoSpiceViewClass *klass) {
	GObjectClass *object_class = G_OBJECT_CLASS(klass);
	GtkWidgetClass *widget_class = GTK_WIDGET_CLASS(klass);

	object_class->dispose = ryo_spice_view_dispose;
	widget_class->snapshot = ryo_spice_view_snapshot;
	widget_class->measure = ryo_spice_view_measure;
}

static void ryo_spice_view_init(RyoSpiceView *self) {
	gtk_widget_set_hexpand(GTK_WIDGET(self), TRUE);
	gtk_widget_set_vexpand(GTK_WIDGET(self), TRUE);
}

GtkWidget *ryo_spice_view_new(void) {
	return g_object_new(RYO_TYPE_SPICE_VIEW, NULL);
}

SpiceDisplayChannel *ryo_spice_view_get_channel(RyoSpiceView *view) {
	return view->channel;
}

gboolean ryo_spice_view_get_guest_size(RyoSpiceView *view, int *w, int *h) {
	if (!view->texture) {
		return FALSE;
	}
	*w = gdk_texture_get_width(view->texture);
	*h = gdk_texture_get_height(view->texture);
	return TRUE;
}

/* GdkDmabufTextureBuilder's destroy-notify fires once GSK is done importing
 * the fd (which may be well after this frame's gl-draw handler returns);
 * we own a dup()'d fd specifically so its lifetime doesn't depend on
 * SPICE's original fd, which the server can close/reuse the moment we
 * call spice_display_channel_gl_draw_done(). */
static void close_dmabuf_fd(gpointer data) {
	close(GPOINTER_TO_INT(data));
}

static void on_gl_draw(SpiceDisplayChannel *channel, guint x, guint y, guint width,
                        guint height, gpointer user_data) {
	RyoSpiceView *self = RYO_SPICE_VIEW(user_data);
	(void)x;
	(void)y;
	(void)width;
	(void)height;

	const SpiceGlScanout *scanout = spice_display_channel_get_gl_scanout(channel);
	if (!scanout || scanout->fd < 0) {
		spice_display_channel_gl_draw_done(channel);
		return;
	}

	int fd_dup = dup(scanout->fd);
	if (fd_dup < 0) {
		g_warning("ryospice: dup() of scanout fd failed: %s", g_strerror(errno));
		spice_display_channel_gl_draw_done(channel);
		return;
	}

	GdkDmabufTextureBuilder *builder = gdk_dmabuf_texture_builder_new();
	gdk_dmabuf_texture_builder_set_display(builder, gtk_widget_get_display(GTK_WIDGET(self)));
	gdk_dmabuf_texture_builder_set_width(builder, scanout->width);
	gdk_dmabuf_texture_builder_set_height(builder, scanout->height);
	gdk_dmabuf_texture_builder_set_fourcc(builder, scanout->format);
	gdk_dmabuf_texture_builder_set_modifier(builder, DRM_FORMAT_MOD_LINEAR);
	gdk_dmabuf_texture_builder_set_n_planes(builder, 1);
	gdk_dmabuf_texture_builder_set_fd(builder, 0, fd_dup);
	gdk_dmabuf_texture_builder_set_stride(builder, 0, scanout->stride);
	gdk_dmabuf_texture_builder_set_offset(builder, 0, 0);

	GError *error = NULL;
	GdkTexture *texture =
	    gdk_dmabuf_texture_builder_build(builder, close_dmabuf_fd, GINT_TO_POINTER(fd_dup), &error);
	g_object_unref(builder);

	if (!texture) {
		g_warning("ryospice: dmabuf texture import failed: %s", error ? error->message : "?");
		g_clear_error(&error);
		close(fd_dup);
		spice_display_channel_gl_draw_done(channel);
		return;
	}

	self->y0top = scanout->y0top;
	g_set_object(&self->texture, texture);
	g_object_unref(texture);
	gtk_widget_queue_draw(GTK_WIDGET(self));

	/* Backpressure: the guest can't render its next frame until this
	 * fires. We've already imported the fd above, so it's safe to ack
	 * now rather than waiting for GSK to actually composite it. */
	spice_display_channel_gl_draw_done(channel);
}

static void on_channel_new(SpiceSession *session, SpiceChannel *channel, gpointer user_data) {
	RyoSpiceView *self = RYO_SPICE_VIEW(user_data);
	(void)session;

	if (!SPICE_IS_DISPLAY_CHANNEL(channel) || self->channel) {
		return;
	}
	/* spice_channel_get_channel_id() isn't in every spice-gtk version we
	 * might build against; the "channel-id" property is the stable form. */
	gint channel_id = -1;
	g_object_get(channel, "channel-id", &channel_id, NULL);
	if (channel_id != 0) {
		return; /* v1: single monitor only */
	}

	self->channel = SPICE_DISPLAY_CHANNEL(channel);
	g_signal_connect(channel, "gl-draw", G_CALLBACK(on_gl_draw), self);
	spice_channel_connect(channel);
}

void ryo_spice_view_attach_session(RyoSpiceView *view, SpiceSession *session) {
	g_signal_connect(session, "channel-new", G_CALLBACK(on_channel_new), view);
}
