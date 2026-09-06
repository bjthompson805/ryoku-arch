#pragma once

#include <gtk/gtk.h>
#include <spice-client.h>

G_BEGIN_DECLS

#define RYO_TYPE_SPICE_VIEW (ryo_spice_view_get_type())
G_DECLARE_FINAL_TYPE(RyoSpiceView, ryo_spice_view, RYO, SPICE_VIEW, GtkWidget)

GtkWidget *ryo_spice_view_new(void);

/* Watches session for the (single, id-0) display channel and renders its
 * GL scanout as it updates. Safe to call before the session is connected. */
void ryo_spice_view_attach_session(RyoSpiceView *view, SpiceSession *session);

/* NULL once no display channel has produced a frame yet. */
SpiceDisplayChannel *ryo_spice_view_get_channel(RyoSpiceView *view);

/* FALSE (and *w/*h left untouched) until the first frame has arrived. */
gboolean ryo_spice_view_get_guest_size(RyoSpiceView *view, int *w, int *h);

G_END_DECLS
