-- Glass: a frosted, translucent finish, loaded as the active Ryoku theme. The
-- heavy blur and window transparency come from the look block; here we raise the
-- blur vibrancy and drive windows with a gentle overshoot so they pop into place.
hl.config({
  decoration = {
    rounding_power = 2,
    blur = { vibrancy = 0.4, noise = 0.0 },
  },
})

hl.curve("ryokuTheme", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1.0 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "ryokuTheme" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "ryokuTheme" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "ryokuTheme" })
