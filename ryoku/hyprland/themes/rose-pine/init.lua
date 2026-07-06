-- rose-pine: motion (active theme).
hl.curve("ryokuTheme", { type = "bezier", points = { { 0.4, 1.0 }, { 0.3, 1.0 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "ryokuTheme" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "ryokuTheme" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "ryokuTheme" })
