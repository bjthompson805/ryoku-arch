#pragma once

#include <gtk/gtk.h>
#include <spice-client.h>

G_BEGIN_DECLS

/* Text-only clipboard sync (both directions) between the host's GdkClipboard
 * and the guest's SpiceMainChannel clipboard-selection signals. */
void ryo_spice_clipboard_attach(GtkWidget *view, SpiceSession *session);

G_END_DECLS
