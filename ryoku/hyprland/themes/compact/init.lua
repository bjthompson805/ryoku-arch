-- Compact: a dense, soft-pop motion, loaded as the active Ryoku theme. The tight
-- gaps, light rounding and dropped shadow come from the look block; here a curve
-- with a whisper of overshoot gives windows a soft spring as they settle.
hl.curve("ryokuTheme", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "ryokuTheme" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "ryokuTheme" })
hl.animation({ leaf = "fade", enabled = true, speed = 6, bezier = "ryokuTheme" })
