#include "input.h"

#include <spice/enums.h>

#include "keymap.h"

typedef struct {
	RyoSpiceView *view;         /* borrowed; outlives this (app-lifetime) */
	SpiceInputsChannel *channel; /* borrowed; NULL until the channel opens */
	gint button_state;           /* bitmask of currently-held SPICE_MOUSE_BUTTON_MASK_* */
} InputCtx;

static gint gdk_button_to_spice(guint gdk_button, gint *mask_out) {
	switch (gdk_button) {
	case 1: *mask_out = SPICE_MOUSE_BUTTON_MASK_LEFT; return SPICE_MOUSE_BUTTON_LEFT;
	case 2: *mask_out = SPICE_MOUSE_BUTTON_MASK_MIDDLE; return SPICE_MOUSE_BUTTON_MIDDLE;
	case 3: *mask_out = SPICE_MOUSE_BUTTON_MASK_RIGHT; return SPICE_MOUSE_BUTTON_RIGHT;
	case 8: *mask_out = SPICE_MOUSE_BUTTON_MASK_SIDE; return SPICE_MOUSE_BUTTON_SIDE;
	case 9: *mask_out = SPICE_MOUSE_BUTTON_MASK_EXTRA; return SPICE_MOUSE_BUTTON_EXTRA;
	default: *mask_out = 0; return SPICE_MOUSE_BUTTON_INVALID;
	}
}

/* Widget-local (x, y) -> guest pixel coordinates. Ignores the widget's own
 * padding/margins (there are none here) and, like display.c's snapshot,
 * ignores aspect ratio -- ryovm always sizes the guest to the window. */
static gboolean widget_to_guest_xy(InputCtx *ctx, double x, double y, gint *gx, gint *gy) {
	int guest_w, guest_h;
	if (!ryo_spice_view_get_guest_size(ctx->view, &guest_w, &guest_h)) {
		return FALSE;
	}
	int widget_w = gtk_widget_get_width(GTK_WIDGET(ctx->view));
	int widget_h = gtk_widget_get_height(GTK_WIDGET(ctx->view));
	if (widget_w <= 0 || widget_h <= 0) {
		return FALSE;
	}
	*gx = (gint)(x * guest_w / widget_w);
	*gy = (gint)(y * guest_h / widget_h);
	return TRUE;
}

/* The guest already renders its own cursor at the position we forward via
 * spice_inputs_channel_position() -- leaving the host's normal GTK pointer
 * visible too gives two overlapping cursors that don't quite track each
 * other (SPICE forwarding has some latency). Every real SPICE client hides
 * the local cursor over the display for exactly this reason. */
static void on_enter(GtkEventControllerMotion *controller, double x, double y,
                      gpointer user_data) {
	(void)x;
	(void)y;
	InputCtx *ctx = user_data;
	GtkWidget *widget = GTK_WIDGET(ctx->view);
	gtk_widget_set_cursor_from_name(widget, "none");

	/* Super (and other compositor-reserved combos) never reach a normal
	 * client window -- Hyprland grabs them globally first. This is the
	 * GTK4/Wayland API built for exactly this case (remote-desktop/VM
	 * viewers needing every key forwarded): request all shortcuts back
	 * for as long as the pointer is over the guest's display. */
	GdkSurface *surface = gtk_native_get_surface(gtk_widget_get_native(widget));
	if (GDK_IS_TOPLEVEL(surface)) {
		gdk_toplevel_inhibit_system_shortcuts(GDK_TOPLEVEL(surface), NULL);
	}
	(void)controller;
}

static void on_leave(GtkEventControllerMotion *controller, gpointer user_data) {
	InputCtx *ctx = user_data;
	GtkWidget *widget = GTK_WIDGET(ctx->view);
	gtk_widget_set_cursor(widget, NULL); /* back to the default pointer */

	GdkSurface *surface = gtk_native_get_surface(gtk_widget_get_native(widget));
	if (GDK_IS_TOPLEVEL(surface)) {
		gdk_toplevel_restore_system_shortcuts(GDK_TOPLEVEL(surface));
	}
	(void)controller;
}

static void on_motion(GtkEventControllerMotion *controller, double x, double y,
                       gpointer user_data) {
	(void)controller;
	InputCtx *ctx = user_data;
	gint gx, gy;
	if (!ctx->channel || !widget_to_guest_xy(ctx, x, y, &gx, &gy)) {
		return;
	}
	spice_inputs_channel_position(ctx->channel, gx, gy, 0, ctx->button_state);
}

static void on_pressed(GtkGestureClick *gesture, gint n_press, double x, double y,
                        gpointer user_data) {
	(void)n_press;
	InputCtx *ctx = user_data;
	guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
	gint mask;
	gint spice_button = gdk_button_to_spice(button, &mask);
	if (spice_button == SPICE_MOUSE_BUTTON_INVALID || !ctx->channel) {
		return;
	}
	gtk_widget_grab_focus(GTK_WIDGET(ctx->view));
	ctx->button_state |= mask;
	gint gx, gy;
	if (widget_to_guest_xy(ctx, x, y, &gx, &gy)) {
		spice_inputs_channel_position(ctx->channel, gx, gy, 0, ctx->button_state);
	}
	spice_inputs_channel_button_press(ctx->channel, spice_button, ctx->button_state);
}

static void on_released(GtkGestureClick *gesture, gint n_press, double x, double y,
                         gpointer user_data) {
	(void)n_press;
	(void)x;
	(void)y;
	InputCtx *ctx = user_data;
	guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
	gint mask;
	gint spice_button = gdk_button_to_spice(button, &mask);
	if (spice_button == SPICE_MOUSE_BUTTON_INVALID || !ctx->channel) {
		return;
	}
	ctx->button_state &= ~mask;
	spice_inputs_channel_button_release(ctx->channel, spice_button, ctx->button_state);
}

/* Scroll wheel has no dedicated SPICE message: the wire protocol models it
 * as an immediate press+release of the UP/DOWN "buttons", same convention
 * X11 has always used. */
static gboolean on_scroll(GtkEventControllerScroll *controller, double dx, double dy,
                           gpointer user_data) {
	(void)controller;
	(void)dx;
	InputCtx *ctx = user_data;
	if (!ctx->channel || dy == 0) {
		return FALSE;
	}
	gint button = (dy < 0) ? SPICE_MOUSE_BUTTON_UP : SPICE_MOUSE_BUTTON_DOWN;
	gint mask = (dy < 0) ? SPICE_MOUSE_BUTTON_MASK_UP : SPICE_MOUSE_BUTTON_MASK_DOWN;
	spice_inputs_channel_button_press(ctx->channel, button, ctx->button_state | mask);
	spice_inputs_channel_button_release(ctx->channel, button, ctx->button_state);
	return TRUE;
}

static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode,
                                GdkModifierType state, gpointer user_data) {
	(void)controller;
	(void)keyval;
	(void)state;
	InputCtx *ctx = user_data;
	guint16 scancode = ryo_spice_keymap_scancode(keycode);
	if (!ctx->channel || scancode == 0) {
		return FALSE;
	}
	spice_inputs_channel_key_press(ctx->channel, scancode);
	return TRUE;
}

static gboolean on_key_released(GtkEventControllerKey *controller, guint keyval, guint keycode,
                                 GdkModifierType state, gpointer user_data) {
	(void)controller;
	(void)keyval;
	(void)state;
	InputCtx *ctx = user_data;
	guint16 scancode = ryo_spice_keymap_scancode(keycode);
	if (!ctx->channel || scancode == 0) {
		return FALSE;
	}
	spice_inputs_channel_key_release(ctx->channel, scancode);
	return TRUE;
}

static void on_channel_new(SpiceSession *session, SpiceChannel *channel, gpointer user_data) {
	(void)session;
	InputCtx *ctx = user_data;
	if (!SPICE_IS_INPUTS_CHANNEL(channel)) {
		return;
	}
	ctx->channel = SPICE_INPUTS_CHANNEL(channel);
	spice_channel_connect(channel);
}

void ryo_spice_input_attach(RyoSpiceView *view, SpiceSession *session) {
	/* App-lifetime: one view, one session, freed when the process exits. */
	InputCtx *ctx = g_new0(InputCtx, 1);
	ctx->view = view;

	g_signal_connect(session, "channel-new", G_CALLBACK(on_channel_new), ctx);

	GtkWidget *widget = GTK_WIDGET(view);
	gtk_widget_set_can_focus(widget, TRUE);
	gtk_widget_set_focusable(widget, TRUE);

	GtkEventController *motion = gtk_event_controller_motion_new();
	g_signal_connect(motion, "motion", G_CALLBACK(on_motion), ctx);
	g_signal_connect(motion, "enter", G_CALLBACK(on_enter), ctx);
	g_signal_connect(motion, "leave", G_CALLBACK(on_leave), ctx);
	gtk_widget_add_controller(widget, motion);

	GtkGesture *click = gtk_gesture_click_new();
	gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), 0); /* any button */
	g_signal_connect(click, "pressed", G_CALLBACK(on_pressed), ctx);
	g_signal_connect(click, "released", G_CALLBACK(on_released), ctx);
	gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click));

	GtkEventController *scroll =
	    gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
	g_signal_connect(scroll, "scroll", G_CALLBACK(on_scroll), ctx);
	gtk_widget_add_controller(widget, scroll);

	/* Capture phase: some keys (Tab, arrows) would otherwise be consumed
	 * by GTK's own focus navigation before reaching a bubble-phase
	 * handler on this widget. */
	GtkEventController *key = gtk_event_controller_key_new();
	gtk_event_controller_set_propagation_phase(key, GTK_PHASE_CAPTURE);
	g_signal_connect(key, "key-pressed", G_CALLBACK(on_key_pressed), ctx);
	g_signal_connect(key, "key-released", G_CALLBACK(on_key_released), ctx);
	gtk_widget_add_controller(widget, key);
}
