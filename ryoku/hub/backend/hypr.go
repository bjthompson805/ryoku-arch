package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// system-level (Hyprland) tweaks the Hub exposes, persisted as one JSON store
// and rendered into one Lua file the live config loads. the store at
// ~/.config/ryoku/hypr.json is the editable truth; settings.lua at
// ~/.config/hypr/ is generated from it and require()d by hyprland.lua after the
// base modules and before user.lua, so settings.lua overrides the shipped
// defaults and a hand-written user.lua still wins over both.
//
// only divergences from the defaults are written, so an untouched setting falls
// through to its base module (and picks up future base improvements) rather
// than being pinned. live edits apply flash-free via `hyprctl eval` (the hl
// API); Save persists + reloads to lock the state in, which also handles the
// removals (a dropped rule or bind) eval can't undo.

// Appearance: general / decoration / animations keywords.
type Appearance struct {
	GapsIn          int     `json:"gapsIn"`
	GapsOut         int     `json:"gapsOut"`
	BorderSize      int     `json:"borderSize"`
	Rounding        int     `json:"rounding"`
	RoundingPower   float64 `json:"roundingPower"`
	ActiveOpacity   float64 `json:"activeOpacity"`
	InactiveOpacity float64 `json:"inactiveOpacity"`
	DimInactive     bool    `json:"dimInactive"`
	DimStrength     float64 `json:"dimStrength"`
	BlurEnabled     bool    `json:"blurEnabled"`
	BlurSize        int     `json:"blurSize"`
	BlurPasses      int     `json:"blurPasses"`
	BlurXray        bool    `json:"blurXray"`
	BlurVibrancy    float64 `json:"blurVibrancy"`
	BlurNoise       float64 `json:"blurNoise"`
	ShadowEnabled   bool    `json:"shadowEnabled"`
	ShadowRange     int     `json:"shadowRange"`
	ShadowPower     int     `json:"shadowPower"`
	GlowEnabled     bool    `json:"glowEnabled"`
	GlowRange       int     `json:"glowRange"`
	GlowColor       string  `json:"glowColor"`
	Animations      bool    `json:"animations"`
	Layout          string  `json:"layout"`
	ActiveBorder    string  `json:"activeBorder"`
	InactiveBorder  string  `json:"inactiveBorder"`
	ResizeOnBorder  bool    `json:"resizeOnBorder"`
	SnapEnabled     bool    `json:"snapEnabled"`
}

// Input: the input keyword (keyboard, pointer, touchpad) + the pointer-adjacent
// misc/gestures keys the Input page edits alongside them.
type Input struct {
	KbLayout           string  `json:"kbLayout"`
	KbVariant          string  `json:"kbVariant"`
	KbOptions          string  `json:"kbOptions"`
	NumlockByDefault   bool    `json:"numlockByDefault"`
	FollowMouse        int     `json:"followMouse"`
	Sensitivity        float64 `json:"sensitivity"`
	AccelProfile       string  `json:"accelProfile"`
	LeftHanded         bool    `json:"leftHanded"`
	MouseNaturalScroll bool    `json:"mouseNaturalScroll"`
	MouseScrollFactor  float64 `json:"mouseScrollFactor"`
	MiddleClickPaste   bool    `json:"middleClickPaste"`
	NaturalScroll      bool    `json:"naturalScroll"`
	TapToClick         bool    `json:"tapToClick"`
	TapAndDrag         bool    `json:"tapAndDrag"`
	Clickfinger        bool    `json:"clickfinger"`
	MiddleEmulation    bool    `json:"middleEmulation"`
	TouchScrollFactor  float64 `json:"touchScrollFactor"`
	DisableWhileTyping bool    `json:"disableWhileTyping"`
	RepeatRate         int     `json:"repeatRate"`
	RepeatDelay        int     `json:"repeatDelay"`
	WorkspaceSwipe     bool    `json:"workspaceSwipe"`
	SwipeFingers       int     `json:"swipeFingers"`
	SwipeInvert        bool    `json:"swipeInvert"`
	SwipeCreateNew     bool    `json:"swipeCreateNew"`
	SwipeDistance      int     `json:"swipeDistance"`
}

// Cursor: theme + size + the cursor-section niceties. live = `hyprctl
// setcursor`. persisted as env in settings.lua (so spawned apps see it) + a
// start hook that wins over the base autostart's setcursor (which registers
// earlier).
type Cursor struct {
	Theme           string `json:"theme"`
	Size            int    `json:"size"`
	InactiveTimeout int    `json:"inactiveTimeout"`
	HideOnKeyPress  bool   `json:"hideOnKeyPress"`
}

type EnvVar struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// WindowRule = one user rule: optional class/title match + one action. Action is
// the rule keyword; Value carries its argument where one applies (opacity, size,
// move, workspace).
type WindowRule struct {
	Class  string `json:"class"`
	Title  string `json:"title"`
	Action string `json:"action"`
	Value  string `json:"value"`
}

// LayerRule: target a layer-shell surface by namespace (bar, launcher, notif
// daemon). Action = the rule; Value = the argument for ignorealpha/dimaround.
type LayerRule struct {
	Namespace string `json:"namespace"`
	Action    string `json:"action"`
	Value     string `json:"value"`
}

type Autostart struct {
	Command string `json:"command"`
}

// Keybind = a user shortcut. action "exec" runs Value; the dispatcher actions
// (close, fullscreen, togglefloating) take no value.
type Keybind struct {
	Keys   string `json:"keys"`
	Action string `json:"action"`
	Value  string `json:"value"`
}

// AnimCurve = a user bezier. P0/P3 fixed at (0,0) and (1,1); only the two
// control points stored. redefining a base name overrides it.
type AnimCurve struct {
	Name string  `json:"name"`
	X0   float64 `json:"x0"`
	Y0   float64 `json:"y0"`
	X1   float64 `json:"x1"`
	Y1   float64 `json:"y1"`
}

// AnimItem: override one animation leaf (windows, fade, workspaces, ...).
type AnimItem struct {
	Leaf    string  `json:"leaf"`
	Enabled bool    `json:"enabled"`
	Speed   float64 `json:"speed"`
	Bezier  string  `json:"bezier"`
	Style   string  `json:"style"`
}

// Anim: per-leaf + per-curve overrides (the global on/off lives in Appearance).
// curves first, items second -- items may reference the curves.
type Anim struct {
	Items  []AnimItem  `json:"items"`
	Curves []AnimCurve `json:"curves"`
}

type Overrides struct {
	Appearance  Appearance   `json:"appearance"`
	Input       Input        `json:"input"`
	Cursor      Cursor       `json:"cursor"`
	Env         []EnvVar     `json:"env"`
	WindowRules []WindowRule `json:"windowRules"`
	Autostart   []Autostart  `json:"autostart"`
	Keybinds    []Keybind    `json:"keybinds"`
	Anim        Anim         `json:"anim"`
	LayerRules  []LayerRule  `json:"layerRules"`

	// inputSaved: the store carries an explicit input section, i.e. the user has
	// saved input settings through the hub at least once. genConfig then pins the
	// kb_* keys unconditionally, so a saved layout (even "us") beats keyboard.lua,
	// which loads earlier and would otherwise silently win.
	inputSaved bool
}

// defaultOverrides mirrors the shipped Hyprland modules (decoration.lua,
// input.lua, keyboard.lua, env.lua/autostart.lua cursor) so the UI shows the
// real baseline and "Reset to defaults" actually restores it. keep these in
// step with the base; only divergence from here is ever written to settings.lua.
func defaultOverrides() Overrides {
	return Overrides{
		Appearance: Appearance{
			GapsIn: 12, GapsOut: 18, BorderSize: 2, Rounding: 2, RoundingPower: 4,
			ActiveOpacity: 1, InactiveOpacity: 0.94,
			DimInactive: false, DimStrength: 0.5,
			BlurEnabled: true, BlurSize: 4, BlurPasses: 1,
			BlurXray: false, BlurVibrancy: 0.17, BlurNoise: 0.01,
			ShadowEnabled: true, ShadowRange: 45, ShadowPower: 4,
			GlowEnabled: false, GlowRange: 10, GlowColor: "#ee33cc",
			Animations: true, Layout: "dwindle",
			ActiveBorder: "#e0563b", InactiveBorder: "#313a4d",
			ResizeOnBorder: true, SnapEnabled: false,
		},
		Input: Input{
			KbLayout: "us", KbVariant: "", KbOptions: "", NumlockByDefault: false,
			FollowMouse: 2, Sensitivity: 0, AccelProfile: "",
			LeftHanded: false, MouseNaturalScroll: false, MouseScrollFactor: 1,
			MiddleClickPaste: true,
			NaturalScroll: false, TapToClick: true, TapAndDrag: true,
			Clickfinger: false, MiddleEmulation: false, TouchScrollFactor: 1,
			DisableWhileTyping: true,
			RepeatRate: 25, RepeatDelay: 600,
			WorkspaceSwipe: false, SwipeFingers: 3,
			SwipeInvert: true, SwipeCreateNew: true, SwipeDistance: 300,
		},
		Cursor:      Cursor{Theme: "Bibata-Modern-Ice", Size: 24, InactiveTimeout: 0, HideOnKeyPress: false},
		Env:         []EnvVar{},
		WindowRules: []WindowRule{},
		Autostart:   []Autostart{},
		Keybinds:    []Keybind{},
		Anim:        Anim{Items: []AnimItem{}, Curves: []AnimCurve{}},
		LayerRules:  []LayerRule{},
	}
}

func hyprStorePath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "hypr.json")
}

func hyprConfigDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "hypr")
}

func generatedLuaPath() string {
	return filepath.Join(hyprConfigDir(), "settings.lua")
}

// loadOverrides: read the store, overlay on the defaults. a partial or older
// store still yields a complete object (missing fields keep the default).
// while no input settings were ever saved, the kb_* baseline comes from the
// live compositor (keyboard.lua may have seeded a non-us layout at install),
// so the hub reports the truth instead of the hardcoded "us".
func loadOverrides() Overrides {
	o := defaultOverrides()
	b, err := os.ReadFile(hyprStorePath())
	if err == nil {
		o.inputSaved = storeHasInput(b)
	}
	if !o.inputSaved {
		liveKbDefaults(&o.Input)
	}
	if err == nil {
		_ = json.Unmarshal(b, &o)
	}
	if o.Env == nil {
		o.Env = []EnvVar{}
	}
	if o.WindowRules == nil {
		o.WindowRules = []WindowRule{}
	}
	if o.Autostart == nil {
		o.Autostart = []Autostart{}
	}
	if o.Keybinds == nil {
		o.Keybinds = []Keybind{}
	}
	if o.Anim.Items == nil {
		o.Anim.Items = []AnimItem{}
	}
	if o.Anim.Curves == nil {
		o.Anim.Curves = []AnimCurve{}
	}
	if o.LayerRules == nil {
		o.LayerRules = []LayerRule{}
	}
	return o
}

// storeHasInput reports whether the stored JSON carries an explicit input
// section. saveOverrides always writes the full struct, so a present input key
// means the user saved input settings at least once.
func storeHasInput(b []byte) bool {
	var probe struct {
		Input json.RawMessage `json:"input"`
	}
	if json.Unmarshal(b, &probe) != nil {
		return false
	}
	return len(probe.Input) > 0 && string(probe.Input) != "null"
}

// liveKbDefaults asks the running compositor for its effective kb_* values
// (`hyprctl getoption -j`, read-only) so the unsaved baseline matches the real
// session. on failure (headless, no hyprctl) the hardcoded defaults stand.
func liveKbDefaults(in *Input) {
	opts := []struct {
		name string
		dst  *string
	}{
		{"input:kb_layout", &in.KbLayout},
		{"input:kb_variant", &in.KbVariant},
		{"input:kb_options", &in.KbOptions},
	}
	for _, o := range opts {
		b, err := exec.Command("hyprctl", "getoption", o.name, "-j").Output()
		if err != nil {
			continue
		}
		var v struct {
			Str string `json:"str"`
		}
		if json.Unmarshal(b, &v) != nil {
			continue
		}
		if s := strings.TrimSpace(v.Str); s != "" {
			*o.dst = s
		}
	}
}

func saveOverrides(o Overrides) error {
	p := hyprStorePath()
	b, err := json.MarshalIndent(o, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(p, b, 0o644)
}

func atomicWrite(path string, b []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	if _, err := f.Write(b); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Chmod(mode); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func parseOverrides(s string) (Overrides, error) {
	o := defaultOverrides()
	if err := json.Unmarshal([]byte(s), &o); err != nil {
		return o, fmt.Errorf("parse overrides JSON: %w", err)
	}
	// a hub snapshot carries explicit input values; saving it pins the kb_* keys.
	o.inputSaved = true
	return o, nil
}

// runHypr: dispatch for `ryoku-hub hypr <sub> [arg]`.
func runHypr(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("hypr needs get|defaults|save|preview|restore|cursors|layouts|variants")
	}
	switch args[0] {
	case "get":
		o := loadOverrides()
		// a pre-migration theme.lua folds into the store once, so the UI shows
		// the live look instead of fighting it. no reload needed: the folded
		// values equal what the stale copy already applied.
		_ = healThemeLua(&o)
		_ = writeGeneratedLua(o) // re-emit settings.lua if a deploy wiped it
		return printJSON(o)
	case "defaults":
		return printJSON(defaultOverrides())
	case "save":
		if len(args) < 2 {
			return fmt.Errorf("hypr save needs a JSON argument")
		}
		o, err := parseOverrides(args[1])
		if err != nil {
			return err
		}
		if err := saveOverrides(o); err != nil {
			return err
		}
		if err := writeGeneratedLua(o); err != nil {
			return err
		}
		hyprReload()
		return nil
	case "preview":
		if len(args) < 2 {
			return fmt.Errorf("hypr preview needs a JSON argument")
		}
		o, err := parseOverrides(args[1])
		if err != nil {
			return err
		}
		hyprEval(liveLua(o))
		return nil
	case "restore":
		// revert the live session to the saved state by reloading (settings.lua +
		// base modules). resets every keyword exactly, including ones eval can't
		// push back to a default. the cursor is set imperatively (setcursor), so a
		// reload alone would leave a previewed cursor live; re-assert the saved one.
		hyprReload()
		o := loadOverrides()
		_ = exec.Command("hyprctl", "setcursor", o.Cursor.Theme, fmt.Sprintf("%d", o.Cursor.Size)).Run()
		return nil
	case "cursors":
		return printJSON(listCursorThemes())
	case "layouts":
		return printJSON(listKbLayouts())
	case "variants":
		if len(args) < 2 {
			return fmt.Errorf("hypr variants needs a layout code")
		}
		return printJSON(listKbVariants(args[1]))
	case "themes":
		return printJSON(listThemes())
	case "theme":
		if len(args) < 2 {
			return fmt.Errorf("hypr theme needs a slug")
		}
		return applyTheme(args[1])
	case "colorsource":
		if len(args) < 2 {
			return fmt.Errorf("hypr colorsource needs follow|fixed")
		}
		return setFollowWallpaper(args[1] == "follow")
	case "scheme":
		if len(args) < 2 {
			return printJSON(map[string]string{"scheme": currentScheme()})
		}
		return applyScheme(args[1])
	default:
		return fmt.Errorf("unknown hypr subcommand: %s", args[0])
	}
}

func printJSON(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	os.Stdout.Write(b)
	fmt.Println()
	return nil
}

func hyprEval(lua string) {
	if strings.TrimSpace(lua) == "" {
		return
	}
	_ = exec.Command("hyprctl", "eval", lua).Run()
}

func hyprReload() {
	_ = exec.Command("hyprctl", "reload").Run()
}

// writeGeneratedLua renders settings.lua from the overrides (diffed against the
// shipped defaults) and writes it atomically.
func writeGeneratedLua(o Overrides) error {
	return atomicWrite(generatedLuaPath(), []byte(genLua(o, loadThemeState().FollowWallpaper)), 0o644)
}

// --- Lua generation -------------------------------------------------------

const luaHeader = `-- Generated by Ryoku Settings (ryoku-hub). Do not edit by hand; it is
-- overwritten on every change. Loaded by hyprland.lua after the base modules and
-- before user.lua, so these tweaks override the shipped defaults while your own
-- user.lua still wins. Manage these in Ryoku Settings (Super + ,).

`

func genLua(o Overrides, follow bool) string {
	var b strings.Builder
	b.WriteString(luaHeader)

	if cfg := genConfig(o, follow); cfg != "" {
		b.WriteString(cfg)
	}
	if anim := genAnimBlock(o); anim != "" {
		b.WriteString(anim)
		b.WriteString("\n")
	}
	if g := genGesture(o); g != "" {
		b.WriteString(g)
		b.WriteString("\n")
	}
	// cursor divergence exports env too: env.lua exports the base theme early
	// and a later hl.env wins, so spawned apps see the picked cursor (the start
	// hook's setcursor only reaches the compositor + XWayland).
	if d := defaultOverrides().Cursor; o.Cursor.Theme != d.Theme || o.Cursor.Size != d.Size {
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("XCURSOR_THEME"), luaStr(o.Cursor.Theme))
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("XCURSOR_SIZE"), luaStr(fmt.Sprintf("%d", o.Cursor.Size)))
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("HYPRCURSOR_THEME"), luaStr(o.Cursor.Theme))
		fmt.Fprintf(&b, "hl.env(%s, %s)\n\n", luaStr("HYPRCURSOR_SIZE"), luaStr(fmt.Sprintf("%d", o.Cursor.Size)))
	}
	for _, e := range o.Env {
		if strings.TrimSpace(e.Key) == "" {
			continue
		}
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr(e.Key), luaStr(e.Value))
	}
	if len(o.Env) > 0 {
		b.WriteString("\n")
	}
	for i, r := range o.WindowRules {
		if rl := genWindowRule(i, r); rl != "" {
			b.WriteString(rl)
		}
	}
	for i, r := range o.LayerRules {
		if rl := genLayerRule(i, r); rl != "" {
			b.WriteString(rl)
		}
	}
	for _, k := range o.Keybinds {
		if kb := genKeybind(k); kb != "" {
			b.WriteString(kb)
		}
	}
	if start := genStartHook(o); start != "" {
		b.WriteString("\n")
		b.WriteString(start)
	}
	return b.String()
}

// genConfig: one hl.config({...}) holding only the general / decoration / input
// / animations leaves that diverge from the defaults. exception: once input
// settings were saved, the kb_* keys are pinned unconditionally, because
// keyboard.lua loads before settings.lua and a diffed-away "us" would let it
// silently win over what the UI shows.
func genConfig(o Overrides, follow bool) string {
	d := defaultOverrides()
	var general, deco, input, cursor, misc, gestures []string

	a, da := o.Appearance, d.Appearance
	if a.GapsIn != da.GapsIn {
		general = append(general, fmt.Sprintf("gaps_in = %d", a.GapsIn))
	}
	if a.GapsOut != da.GapsOut {
		general = append(general, fmt.Sprintf("gaps_out = %d", a.GapsOut))
	}
	if a.BorderSize != da.BorderSize {
		general = append(general, fmt.Sprintf("border_size = %d", a.BorderSize))
	}
	if a.Layout != da.Layout {
		general = append(general, fmt.Sprintf("layout = %s", luaStr(a.Layout)))
	}
	if a.ResizeOnBorder != da.ResizeOnBorder {
		general = append(general, fmt.Sprintf("resize_on_border = %t", a.ResizeOnBorder))
	}
	if a.SnapEnabled != da.SnapEnabled {
		general = append(general, fmt.Sprintf("snap = { enabled = %t }", a.SnapEnabled))
	}
	if !follow {
		general = append(general, fmt.Sprintf("[\"col.active_border\"] = %s", luaStr(luaRGB(a.ActiveBorder))))
		general = append(general, fmt.Sprintf("[\"col.inactive_border\"] = %s", luaStr(luaRGB(a.InactiveBorder))))
	}

	if a.Rounding != da.Rounding {
		deco = append(deco, fmt.Sprintf("rounding = %d", a.Rounding))
	}
	if a.RoundingPower != da.RoundingPower {
		deco = append(deco, fmt.Sprintf("rounding_power = %s", luaNum(a.RoundingPower)))
	}
	if a.ActiveOpacity != da.ActiveOpacity {
		deco = append(deco, fmt.Sprintf("active_opacity = %s", luaNum(a.ActiveOpacity)))
	}
	if a.InactiveOpacity != da.InactiveOpacity {
		deco = append(deco, fmt.Sprintf("inactive_opacity = %s", luaNum(a.InactiveOpacity)))
	}
	if a.DimInactive != da.DimInactive {
		deco = append(deco, fmt.Sprintf("dim_inactive = %t", a.DimInactive))
	}
	if a.DimStrength != da.DimStrength {
		deco = append(deco, fmt.Sprintf("dim_strength = %s", luaNum(a.DimStrength)))
	}
	var blur []string
	if a.BlurEnabled != da.BlurEnabled {
		blur = append(blur, fmt.Sprintf("enabled = %t", a.BlurEnabled))
	}
	if a.BlurSize != da.BlurSize {
		blur = append(blur, fmt.Sprintf("size = %d", a.BlurSize))
	}
	if a.BlurPasses != da.BlurPasses {
		blur = append(blur, fmt.Sprintf("passes = %d", a.BlurPasses))
	}
	if a.BlurXray != da.BlurXray {
		blur = append(blur, fmt.Sprintf("xray = %t", a.BlurXray))
	}
	if a.BlurVibrancy != da.BlurVibrancy {
		blur = append(blur, fmt.Sprintf("vibrancy = %s", luaNum(a.BlurVibrancy)))
	}
	if a.BlurNoise != da.BlurNoise {
		blur = append(blur, fmt.Sprintf("noise = %s", luaNum(a.BlurNoise)))
	}
	if len(blur) > 0 {
		deco = append(deco, "blur = { "+strings.Join(blur, ", ")+" }")
	}
	var shadow []string
	if a.ShadowEnabled != da.ShadowEnabled {
		shadow = append(shadow, fmt.Sprintf("enabled = %t", a.ShadowEnabled))
	}
	if a.ShadowRange != da.ShadowRange {
		shadow = append(shadow, fmt.Sprintf("range = %d", a.ShadowRange))
	}
	if a.ShadowPower != da.ShadowPower {
		shadow = append(shadow, fmt.Sprintf("render_power = %d", a.ShadowPower))
	}
	if len(shadow) > 0 {
		deco = append(deco, "shadow = { "+strings.Join(shadow, ", ")+" }")
	}
	var glow []string
	if a.GlowEnabled != da.GlowEnabled {
		glow = append(glow, fmt.Sprintf("enabled = %t", a.GlowEnabled))
	}
	if a.GlowRange != da.GlowRange {
		glow = append(glow, fmt.Sprintf("range = %d", a.GlowRange))
	}
	if a.GlowColor != da.GlowColor {
		glow = append(glow, fmt.Sprintf("color = %s", luaStr(luaRGB(a.GlowColor))))
	}
	if len(glow) > 0 {
		deco = append(deco, "glow = { "+strings.Join(glow, ", ")+" }")
	}

	in, di := o.Input, d.Input
	if o.inputSaved {
		input = append(input,
			fmt.Sprintf("kb_layout = %s", luaStr(in.KbLayout)),
			fmt.Sprintf("kb_variant = %s", luaStr(in.KbVariant)),
			fmt.Sprintf("kb_options = %s", luaStr(in.KbOptions)))
	} else {
		if in.KbLayout != di.KbLayout {
			input = append(input, fmt.Sprintf("kb_layout = %s", luaStr(in.KbLayout)))
		}
		if in.KbVariant != di.KbVariant {
			input = append(input, fmt.Sprintf("kb_variant = %s", luaStr(in.KbVariant)))
		}
		if in.KbOptions != di.KbOptions {
			input = append(input, fmt.Sprintf("kb_options = %s", luaStr(in.KbOptions)))
		}
	}
	if in.NumlockByDefault != di.NumlockByDefault {
		input = append(input, fmt.Sprintf("numlock_by_default = %t", in.NumlockByDefault))
	}
	if in.FollowMouse != di.FollowMouse {
		input = append(input, fmt.Sprintf("follow_mouse = %d", in.FollowMouse))
	}
	if in.Sensitivity != di.Sensitivity {
		input = append(input, fmt.Sprintf("sensitivity = %s", luaNum(in.Sensitivity)))
	}
	if in.AccelProfile != di.AccelProfile {
		input = append(input, fmt.Sprintf("accel_profile = %s", luaStr(in.AccelProfile)))
	}
	if in.LeftHanded != di.LeftHanded {
		input = append(input, fmt.Sprintf("left_handed = %t", in.LeftHanded))
	}
	if in.MouseNaturalScroll != di.MouseNaturalScroll {
		input = append(input, fmt.Sprintf("natural_scroll = %t", in.MouseNaturalScroll))
	}
	if in.MouseScrollFactor != di.MouseScrollFactor {
		input = append(input, fmt.Sprintf("scroll_factor = %s", luaNum(in.MouseScrollFactor)))
	}
	if in.RepeatRate != di.RepeatRate {
		input = append(input, fmt.Sprintf("repeat_rate = %d", in.RepeatRate))
	}
	if in.RepeatDelay != di.RepeatDelay {
		input = append(input, fmt.Sprintf("repeat_delay = %d", in.RepeatDelay))
	}
	var touch []string
	if in.NaturalScroll != di.NaturalScroll {
		touch = append(touch, fmt.Sprintf("natural_scroll = %t", in.NaturalScroll))
	}
	if in.TapToClick != di.TapToClick {
		touch = append(touch, fmt.Sprintf("tap_to_click = %t", in.TapToClick))
	}
	if in.TapAndDrag != di.TapAndDrag {
		touch = append(touch, fmt.Sprintf("tap_and_drag = %t", in.TapAndDrag))
	}
	if in.Clickfinger != di.Clickfinger {
		touch = append(touch, fmt.Sprintf("clickfinger_behavior = %t", in.Clickfinger))
	}
	if in.MiddleEmulation != di.MiddleEmulation {
		touch = append(touch, fmt.Sprintf("middle_button_emulation = %t", in.MiddleEmulation))
	}
	if in.TouchScrollFactor != di.TouchScrollFactor {
		touch = append(touch, fmt.Sprintf("scroll_factor = %s", luaNum(in.TouchScrollFactor)))
	}
	if in.DisableWhileTyping != di.DisableWhileTyping {
		touch = append(touch, fmt.Sprintf("disable_while_typing = %t", in.DisableWhileTyping))
	}
	if len(touch) > 0 {
		input = append(input, "touchpad = { "+strings.Join(touch, ", ")+" }")
	}

	c, dc := o.Cursor, d.Cursor
	if c.InactiveTimeout != dc.InactiveTimeout {
		cursor = append(cursor, fmt.Sprintf("inactive_timeout = %d", c.InactiveTimeout))
	}
	if c.HideOnKeyPress != dc.HideOnKeyPress {
		cursor = append(cursor, fmt.Sprintf("hide_on_key_press = %t", c.HideOnKeyPress))
	}

	if in.MiddleClickPaste != di.MiddleClickPaste {
		misc = append(misc, fmt.Sprintf("middle_click_paste = %t", in.MiddleClickPaste))
	}

	if in.SwipeInvert != di.SwipeInvert {
		gestures = append(gestures, fmt.Sprintf("workspace_swipe_invert = %t", in.SwipeInvert))
	}
	if in.SwipeCreateNew != di.SwipeCreateNew {
		gestures = append(gestures, fmt.Sprintf("workspace_swipe_create_new = %t", in.SwipeCreateNew))
	}
	if in.SwipeDistance != di.SwipeDistance {
		gestures = append(gestures, fmt.Sprintf("workspace_swipe_distance = %d", in.SwipeDistance))
	}

	var sections []string
	if len(general) > 0 {
		sections = append(sections, "  general = { "+strings.Join(general, ", ")+" }")
	}
	if len(deco) > 0 {
		sections = append(sections, "  decoration = { "+strings.Join(deco, ", ")+" }")
	}
	if len(input) > 0 {
		sections = append(sections, "  input = { "+strings.Join(input, ", ")+" }")
	}
	if len(cursor) > 0 {
		sections = append(sections, "  cursor = { "+strings.Join(cursor, ", ")+" }")
	}
	if len(misc) > 0 {
		sections = append(sections, "  misc = { "+strings.Join(misc, ", ")+" }")
	}
	if len(gestures) > 0 {
		sections = append(sections, "  gestures = { "+strings.Join(gestures, ", ")+" }")
	}
	if !o.Appearance.Animations {
		sections = append(sections, "  animations = { enabled = false }")
	}
	if len(sections) == 0 {
		return ""
	}
	return "hl.config({\n" + strings.Join(sections, ",\n") + ",\n})\n\n"
}

// windowRuleField maps the pretty boolean action keys the UI stores onto the
// hl.window_rule field names where they differ. a wrong name here errors inside
// settings.lua and silently disables everything after it, so keep this in step
// with the live API (see hypr_test.go's field-name table).
var windowRuleField = map[string]string{
	"nodim": "no_dim", "noanim": "no_anim", "noblur": "no_blur",
	"noshadow": "no_shadow", "nofocus": "no_focus", "stayfocused": "stay_focused",
	"keepaspectratio": "keep_aspect_ratio",
}

func genWindowRule(i int, r WindowRule) string {
	if r.Action == "" {
		return ""
	}
	var match []string
	if r.Class != "" {
		match = append(match, fmt.Sprintf("class = %s", luaStr(r.Class)))
	}
	if r.Title != "" {
		match = append(match, fmt.Sprintf("title = %s", luaStr(r.Title)))
	}
	if len(match) == 0 {
		return ""
	}
	var prop string
	switch r.Action {
	case "float", "tile", "pin", "fullscreen", "maximize", "center", "immediate", "pseudo",
		"opaque", "xray", "nodim", "noanim", "noblur", "noshadow", "nofocus", "stayfocused",
		"keepaspectratio", "norounding", "noborder":
		// boolean effects; the stored action keys stay stable, the emitted Lua
		// field is the hl API name (which is not always the action key).
		field := windowRuleField[r.Action]
		switch r.Action {
		case "norounding":
			prop = "rounding = 0"
		case "noborder":
			prop = "border_size = 0"
		default:
			if field == "" {
				field = r.Action
			}
			prop = field + " = true"
		}
	case "opacity":
		prop = fmt.Sprintf("opacity = %s", luaNum(parseFloat(r.Value, 1)))
	case "size":
		w, h := parseWxH(r.Value)
		prop = fmt.Sprintf("size = { %d, %d }", w, h)
	case "move":
		x, y := parseWxH(r.Value)
		prop = fmt.Sprintf("move = { %d, %d }", x, y)
	case "workspace":
		prop = fmt.Sprintf("workspace = %s", luaStr(r.Value))
	case "idleinhibit":
		v := r.Value
		if v != "always" && v != "focus" && v != "fullscreen" {
			v = "always"
		}
		prop = fmt.Sprintf("idle_inhibit = %s", luaStr(v))
	case "suppressevent":
		v := r.Value
		if v != "maximize" && v != "fullscreen" && v != "activate" && v != "activatefocus" {
			v = "maximize"
		}
		prop = fmt.Sprintf("suppress_event = %s", luaStr(v))
	default:
		return ""
	}
	name := fmt.Sprintf("ryoku-user-%d", i+1)
	return fmt.Sprintf("hl.window_rule({ name = %s, match = { %s }, %s })\n",
		luaStr(name), strings.Join(match, ", "), prop)
}

func genLayerRule(i int, r LayerRule) string {
	if strings.TrimSpace(r.Namespace) == "" || r.Action == "" {
		return ""
	}
	var prop string
	switch r.Action {
	case "blur":
		prop = "blur = true"
	case "noanim":
		prop = "no_anim = true"
	case "blurpopups":
		prop = "blur_popups = true"
	case "xray":
		prop = "xray = true"
	case "abovelock":
		prop = "above_lock = true"
	case "noshadow":
		// legacy action: layer surfaces lost their shadow effect in Hyprland's
		// rule rewrite. drop it instead of emitting a field the runtime rejects
		// (one bad line would kill the whole generated file).
		return ""
	case "ignorealpha":
		prop = fmt.Sprintf("ignore_alpha = %s", luaNum(parseFloat(r.Value, 0.5)))
	case "dimaround":
		// bool in the hl API; the dim amount is decoration:dim_around.
		prop = "dim_around = true"
	default:
		return ""
	}
	name := fmt.Sprintf("ryoku-layer-%d", i+1)
	return fmt.Sprintf("hl.layer_rule({ name = %s, match = { namespace = %s }, %s })\n",
		luaStr(name), luaStr(r.Namespace), prop)
}

func genKeybind(k Keybind) string {
	if strings.TrimSpace(k.Keys) == "" {
		return ""
	}
	var dsp string
	switch k.Action {
	case "exec", "":
		if strings.TrimSpace(k.Value) == "" {
			return ""
		}
		dsp = fmt.Sprintf("hl.dsp.exec_cmd(%s)", luaStr(k.Value))
	case "close":
		dsp = "hl.dsp.window.close()"
	case "fullscreen":
		dsp = "hl.dsp.window.fullscreen()"
	case "togglefloating":
		dsp = "hl.dsp.window.float({ action = \"toggle\" })"
	default:
		return ""
	}
	return fmt.Sprintf("hl.bind(%s, %s)\n", luaStr(k.Keys), dsp)
}

// genStartHook runs the cursor setcursor + any user autostart commands at
// session start. registers after the base autostart, so its setcursor wins.
func genStartHook(o Overrides) string {
	var lines []string
	d := defaultOverrides().Cursor
	if o.Cursor.Theme != d.Theme || o.Cursor.Size != d.Size {
		lines = append(lines, fmt.Sprintf("  hl.exec_cmd(%s)",
			luaStr(fmt.Sprintf("hyprctl setcursor %s %d", o.Cursor.Theme, o.Cursor.Size))))
	}
	for _, a := range o.Autostart {
		if strings.TrimSpace(a.Command) == "" {
			continue
		}
		lines = append(lines, fmt.Sprintf("  hl.exec_cmd(%s)", luaStr(a.Command)))
	}
	if len(lines) == 0 {
		return ""
	}
	return "hl.on(\"hyprland.start\", function()\n" + strings.Join(lines, "\n") + "\nend)\n"
}

// fullConfigLua = every appearance/input leaf set explicitly (not only the
// diffs), so eval forces the exact state, including a value moved back to its
// default. genConfig stays diff-based for settings.lua; the live preview needs
// to reset any key, not only push it away from the baseline.
func fullConfigLua(o Overrides, follow bool) string {
	a, in, c := o.Appearance, o.Input, o.Cursor
	general := []string{
		fmt.Sprintf("gaps_in = %d", a.GapsIn),
		fmt.Sprintf("gaps_out = %d", a.GapsOut),
		fmt.Sprintf("border_size = %d", a.BorderSize),
		fmt.Sprintf("layout = %s", luaStr(a.Layout)),
		fmt.Sprintf("resize_on_border = %t", a.ResizeOnBorder),
		fmt.Sprintf("snap = { enabled = %t }", a.SnapEnabled),
	}
	if !follow {
		general = append(general,
			fmt.Sprintf("[\"col.active_border\"] = %s", luaStr(luaRGB(a.ActiveBorder))),
			fmt.Sprintf("[\"col.inactive_border\"] = %s", luaStr(luaRGB(a.InactiveBorder))))
	}
	deco := []string{
		fmt.Sprintf("rounding = %d", a.Rounding),
		fmt.Sprintf("rounding_power = %s", luaNum(a.RoundingPower)),
		fmt.Sprintf("active_opacity = %s", luaNum(a.ActiveOpacity)),
		fmt.Sprintf("inactive_opacity = %s", luaNum(a.InactiveOpacity)),
		fmt.Sprintf("dim_inactive = %t", a.DimInactive),
		fmt.Sprintf("dim_strength = %s", luaNum(a.DimStrength)),
		fmt.Sprintf("blur = { enabled = %t, size = %d, passes = %d, xray = %t, vibrancy = %s, noise = %s }",
			a.BlurEnabled, a.BlurSize, a.BlurPasses, a.BlurXray, luaNum(a.BlurVibrancy), luaNum(a.BlurNoise)),
		fmt.Sprintf("shadow = { enabled = %t, range = %d, render_power = %d }",
			a.ShadowEnabled, a.ShadowRange, a.ShadowPower),
		fmt.Sprintf("glow = { enabled = %t, range = %d, color = %s }",
			a.GlowEnabled, a.GlowRange, luaStr(luaRGB(a.GlowColor))),
	}
	input := []string{
		fmt.Sprintf("kb_layout = %s", luaStr(in.KbLayout)),
		fmt.Sprintf("kb_variant = %s", luaStr(in.KbVariant)),
		fmt.Sprintf("kb_options = %s", luaStr(in.KbOptions)),
		fmt.Sprintf("numlock_by_default = %t", in.NumlockByDefault),
		fmt.Sprintf("follow_mouse = %d", in.FollowMouse),
		fmt.Sprintf("sensitivity = %s", luaNum(in.Sensitivity)),
		fmt.Sprintf("accel_profile = %s", luaStr(in.AccelProfile)),
		fmt.Sprintf("left_handed = %t", in.LeftHanded),
		fmt.Sprintf("natural_scroll = %t", in.MouseNaturalScroll),
		fmt.Sprintf("scroll_factor = %s", luaNum(in.MouseScrollFactor)),
		fmt.Sprintf("repeat_rate = %d", in.RepeatRate),
		fmt.Sprintf("repeat_delay = %d", in.RepeatDelay),
		fmt.Sprintf("touchpad = { natural_scroll = %t, tap_to_click = %t, tap_and_drag = %t, "+
			"clickfinger_behavior = %t, middle_button_emulation = %t, scroll_factor = %s, disable_while_typing = %t }",
			in.NaturalScroll, in.TapToClick, in.TapAndDrag,
			in.Clickfinger, in.MiddleEmulation, luaNum(in.TouchScrollFactor), in.DisableWhileTyping),
	}
	return "hl.config({\n" +
		"  general = { " + strings.Join(general, ", ") + " },\n" +
		"  decoration = { " + strings.Join(deco, ", ") + " },\n" +
		"  input = { " + strings.Join(input, ", ") + " },\n" +
		fmt.Sprintf("  cursor = { inactive_timeout = %d, hide_on_key_press = %t },\n", c.InactiveTimeout, c.HideOnKeyPress) +
		fmt.Sprintf("  misc = { middle_click_paste = %t },\n", in.MiddleClickPaste) +
		fmt.Sprintf("  gestures = { workspace_swipe_invert = %t, workspace_swipe_create_new = %t, workspace_swipe_distance = %d },\n",
			in.SwipeInvert, in.SwipeCreateNew, in.SwipeDistance) +
		fmt.Sprintf("  animations = { enabled = %t },\n", a.Animations) +
		"})\n"
}

// genAnimItem: one hl.animation override line.
func genAnimItem(it AnimItem) string {
	if strings.TrimSpace(it.Leaf) == "" {
		return ""
	}
	parts := []string{
		fmt.Sprintf("leaf = %s", luaStr(it.Leaf)),
		fmt.Sprintf("enabled = %t", it.Enabled),
		fmt.Sprintf("speed = %s", luaNum(it.Speed)),
	}
	if it.Bezier != "" {
		parts = append(parts, fmt.Sprintf("bezier = %s", luaStr(it.Bezier)))
	}
	if it.Style != "" {
		parts = append(parts, fmt.Sprintf("style = %s", luaStr(it.Style)))
	}
	return fmt.Sprintf("hl.animation({ %s })\n", strings.Join(parts, ", "))
}

// genAnimBlock = the user's bezier curves (first, so the items can reference
// them) + the per-leaf animation overrides.
func genAnimBlock(o Overrides) string {
	var b strings.Builder
	for _, c := range o.Anim.Curves {
		if strings.TrimSpace(c.Name) == "" {
			continue
		}
		fmt.Fprintf(&b, "hl.curve(%s, { type = \"bezier\", points = { { %s, %s }, { %s, %s } } })\n",
			luaStr(c.Name), luaNum(c.X0), luaNum(c.Y0), luaNum(c.X1), luaNum(c.Y1))
	}
	for _, it := range o.Anim.Items {
		if a := genAnimItem(it); a != "" {
			b.WriteString(a)
		}
	}
	return b.String()
}

// genGesture: the workspace-swipe touchpad gesture when enabled. the base
// config ships no gesture, so an empty string leaves swipe off.
func genGesture(o Overrides) string {
	if !o.Input.WorkspaceSwipe {
		return ""
	}
	n := o.Input.SwipeFingers
	if n < 3 {
		n = 3
	}
	return fmt.Sprintf("hl.gesture({ fingers = %d, direction = \"horizontal\", action = \"workspace\" })\n", n)
}

// liveLua = full-config preview + cursor, applied flash-free via hyprctl eval
// (appearance / input / cursor). rules, keybinds, env, autostart are not
// previewed; they apply on Save via reload.
func liveLua(o Overrides) string {
	return fullConfigLua(o, loadThemeState().FollowWallpaper) + genAnimBlock(o) + genGesture(o) +
		fmt.Sprintf("hl.exec_cmd(%s)\n", luaStr(fmt.Sprintf("hyprctl setcursor %s %d", o.Cursor.Theme, o.Cursor.Size)))
}

// --- Lua value helpers ----------------------------------------------------

func luaStr(s string) string {
	r := strings.NewReplacer("\\", "\\\\", "\"", "\\\"", "\n", "\\n", "\r", "\\r")
	return "\"" + r.Replace(s) + "\""
}

func luaNum(f float64) string {
	s := fmt.Sprintf("%g", f)
	if !strings.ContainsAny(s, ".eE") {
		s += ".0"
	}
	return s
}

// luaRGB: "#rrggbb" (or "rrggbb") -> Hyprland's rgb(rrggbb) form.
func luaRGB(hex string) string {
	h := strings.TrimPrefix(strings.TrimSpace(hex), "#")
	return "rgb(" + h + ")"
}

func parseFloat(s string, fallback float64) float64 {
	var f float64
	if _, err := fmt.Sscanf(strings.TrimSpace(s), "%g", &f); err != nil {
		return fallback
	}
	return f
}

// parseWxH: "1500x850" (or "1500 850" / "1500,850") -> two ints.
func parseWxH(s string) (int, int) {
	s = strings.NewReplacer("x", " ", "X", " ", ",", " ").Replace(s)
	var a, b int
	fmt.Sscan(s, &a, &b)
	return a, b
}

// --- environment enumeration ----------------------------------------------

// listCursorThemes: installed cursor themes = icon-theme dirs that contain a
// cursors/ subdir, across the standard search paths, dedup'd and sorted.
func listCursorThemes() []string {
	seen := map[string]bool{}
	for _, dir := range iconSearchDirs() {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			if _, err := os.Stat(filepath.Join(dir, e.Name(), "cursors")); err == nil {
				seen[e.Name()] = true
			}
		}
	}
	out := make([]string, 0, len(seen))
	for n := range seen {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

func iconSearchDirs() []string {
	home := os.Getenv("HOME")
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	return []string{
		filepath.Join(home, ".icons"),
		filepath.Join(dataHome, "icons"),
		"/usr/share/icons",
		"/usr/local/share/icons",
	}
}

// listKbLayouts: X11 keyboard layout codes from the xkb rules base, each as
// {code, name}. falls back to a small common set if the base is absent.
func listKbLayouts() []map[string]string {
	out := parseXkbLayouts("/usr/share/X11/xkb/rules/base.lst")
	if len(out) == 0 {
		out = parseXkbLayouts("/usr/share/X11/xkb/rules/evdev.lst")
	}
	if len(out) == 0 {
		for _, c := range []string{"us", "gb", "de", "fr", "es", "it", "ru", "jp"} {
			out = append(out, map[string]string{"code": c, "name": strings.ToUpper(c)})
		}
	}
	return out
}

// listKbVariants: X11 variant codes for one layout from the xkb rules base,
// each as {code, name}. an unknown layout (or an absent base) yields [].
func listKbVariants(layout string) []map[string]string {
	out := parseXkbVariants("/usr/share/X11/xkb/rules/base.lst", layout)
	if len(out) == 0 {
		out = parseXkbVariants("/usr/share/X11/xkb/rules/evdev.lst", layout)
	}
	if out == nil {
		out = []map[string]string{}
	}
	return out
}

// parseXkbVariants reads the "! variant" block of an xkb rules .lst file and
// keeps the entries for one layout. lines look like
// "  <variant>  <layout>: <description>"; the layout field can carry several
// comma-separated codes, so it is split before matching.
func parseXkbVariants(path, layout string) []map[string]string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []map[string]string
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		t := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(t, "!") {
			in = t == "! variant"
			continue
		}
		if !in || t == "" {
			continue
		}
		fields := strings.Fields(t)
		if len(fields) < 2 {
			continue
		}
		code := fields[0]
		rest := strings.TrimSpace(strings.TrimPrefix(t, code))
		layouts, desc, ok := strings.Cut(rest, ":")
		if !ok {
			continue
		}
		match := false
		for _, l := range strings.Split(layouts, ",") {
			if strings.TrimSpace(l) == layout {
				match = true
				break
			}
		}
		if !match {
			continue
		}
		out = append(out, map[string]string{"code": code, "name": strings.TrimSpace(desc)})
	}
	return out
}

// parseXkbLayouts reads the "! layout" block of an xkb rules .lst file.
func parseXkbLayouts(path string) []map[string]string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []map[string]string
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		t := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(t, "!") {
			in = t == "! layout"
			continue
		}
		if !in || t == "" {
			continue
		}
		fields := strings.Fields(t)
		if len(fields) < 2 {
			continue
		}
		code := fields[0]
		name := strings.TrimSpace(strings.TrimPrefix(t, code))
		out = append(out, map[string]string{"code": code, "name": name})
	}
	return out
}
