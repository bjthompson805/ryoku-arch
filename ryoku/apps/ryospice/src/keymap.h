#pragma once

#include <glib.h>

G_BEGIN_DECLS

/* GTK4's gdk_key_event_get_keycode() returns the X11/XKB-convention
 * "hardware keycode" (evdev keycode + 8) on every GDK backend, Wayland
 * included -- pass that value straight in. Returns 0 for an unmapped or
 * out-of-range keycode. */
guint16 ryo_spice_keymap_scancode(guint hardware_keycode);

G_END_DECLS
