-- Managed by the hardware display script (ryoku-monitor). Edits may be overwritten.
--
-- No per-output line ships on purpose: every display uses the catch-all below
-- until ryoku-monitor writes explicit hl.monitor{} entries (sized to each panel's
-- real pixel density, and setting GDK_SCALE to match). Those come after this seed,
-- so they win. Scale 1 here means a panel is never over-zoomed before autoscale.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})
