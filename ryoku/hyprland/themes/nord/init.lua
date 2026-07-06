-- nord: motion. active ryoku theme.
hl.curve("ryokuTheme", { type = "bezier", points = { { 0.3, 0.9 }, { 0.3, 1.0 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "ryokuTheme" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "ryokuTheme" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "ryokuTheme" })
