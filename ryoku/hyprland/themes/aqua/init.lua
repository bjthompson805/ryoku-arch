-- aqua: motion. active ryoku theme.
hl.curve("ryokuTheme", { type = "bezier", points = { { 0.34, 1.2 }, { 0.4, 1.0 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "ryokuTheme" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "ryokuTheme" })
hl.animation({ leaf = "fade", enabled = true, speed = 6, bezier = "ryokuTheme" })
