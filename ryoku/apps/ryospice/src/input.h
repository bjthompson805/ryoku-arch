#pragma once

#include <gtk/gtk.h>
#include <spice-client.h>

#include "display.h"

G_BEGIN_DECLS

/* Phase B: forwards GTK key/pointer events on `view` to the guest's
 * SpiceInputsChannel once the session opens one. No-op stub for Phase A. */
void ryo_spice_input_attach(RyoSpiceView *view, SpiceSession *session);

G_END_DECLS
