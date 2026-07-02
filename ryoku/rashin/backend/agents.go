package main

import (
	"os"
	"path/filepath"
	"strings"
)

// Foreign-file pointer blocks are fenced with these markers so wiring is
// idempotent and cleanly reversible.
const (
	pointerBegin = "<!-- ryoku-rashin:begin -->"
	pointerEnd   = "<!-- ryoku-rashin:end -->"
)

// PointerBlock is the fenced note appended to each agent's instructions file,
// telling it the vault exists and to read it first.
const PointerBlock = pointerBegin + "\n" +
	"## Ryoku Rashin system vault\n" +
	"\n" +
	"This machine runs Ryoku (Arch Linux, Hyprland desktop). A maintained map of the\n" +
	"system lives at `~/.local/share/ryoku/rashin/`. Before exploring the machine or\n" +
	"guessing paths, read `AGENTS.md` there: it says where every config lives, which\n" +
	"binary owns it, and how to reload it. Write durable notes to `memory/` and\n" +
	"dated notes to `journal/YYYY-MM-DD.md`.\n" +
	pointerEnd

// Agent is a detected coding CLI and its vault-pointer wiring state.
type Agent struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Present bool   `json:"present"`
	Wired   bool   `json:"wired"`
	File    string `json:"file"`
}

// agentDef describes where an agent lives and where its pointer block goes.
// gate is the directory that must already exist before Wire may create file;
// for most agents it equals the agent home, but opencode wires into an
// on-demand ~/.config/opencode as long as ~/.config exists.
type agentDef struct {
	id   string
	name string
	home func() string // the agent's own config dir; Present when it exists
	gate func() string // the dir that must exist for Wire to proceed
	file func() string // the instructions file the pointer block lands in
}

func agentDefs() []agentDef {
	return []agentDef{
		{
			id: "claude", name: "Claude Code",
			home: func() string { return filepath.Join(home(), ".claude") },
			gate: func() string { return filepath.Join(home(), ".claude") },
			file: func() string { return filepath.Join(home(), ".claude", "CLAUDE.md") },
		},
		{
			id: "codex", name: "Codex CLI",
			home: func() string { return filepath.Join(home(), ".codex") },
			gate: func() string { return filepath.Join(home(), ".codex") },
			file: func() string { return filepath.Join(home(), ".codex", "AGENTS.md") },
		},
		{
			id: "opencode", name: "opencode",
			home: func() string { return filepath.Join(configHome(), "opencode") },
			gate: func() string { return configHome() },
			file: func() string { return filepath.Join(configHome(), "opencode", "AGENTS.md") },
		},
		{
			id: "omp", name: "Oh My Pi",
			home: func() string { return filepath.Join(home(), ".omp") },
			gate: func() string { return filepath.Join(home(), ".omp") },
			file: func() string { return filepath.Join(home(), ".omp", "agent", "AGENTS.md") },
		},
	}
}

// DetectAgents reports each known agent's presence and wiring state.
func DetectAgents() []Agent {
	defs := agentDefs()
	out := make([]Agent, 0, len(defs))
	for _, d := range defs {
		out = append(out, Agent{
			ID:      d.id,
			Name:    d.name,
			Present: dirExists(d.home()),
			Wired:   fileHasBlock(d.file()),
			File:    tildeAbbrev(d.file()),
		})
	}
	return out
}

// Wire upserts the pointer block into an agent's file, creating the file (and
// the parent dir only when the agent's gate dir already exists). It never
// creates an agent's home dir; opencode is the sole exception, where the gate
// is ~/.config and Wire may create ~/.config/opencode beneath it.
func Wire(id string) error {
	d, ok := lookupAgent(id)
	if !ok {
		return os.ErrInvalid
	}
	if !dirExists(d.gate()) {
		return &os.PathError{Op: "wire", Path: d.gate(), Err: os.ErrNotExist}
	}
	file := d.file()
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		return err
	}
	doc := readFileOrEmpty(file)
	return atomicWrite(file, []byte(upsertBlock(doc)), 0o644)
}

// Unwire removes the pointer block from an agent's file, keeping the file.
func Unwire(id string) error {
	d, ok := lookupAgent(id)
	if !ok {
		return os.ErrInvalid
	}
	file := d.file()
	doc := readFileOrEmpty(file)
	if doc == "" {
		return nil
	}
	return atomicWrite(file, []byte(removeBlock(doc)), 0o644)
}

// WireAll wires every present agent and returns how many it wired.
func WireAll() int {
	n := 0
	for _, d := range agentDefs() {
		if !dirExists(d.home()) {
			continue
		}
		if Wire(d.id) == nil {
			n++
		}
	}
	return n
}

// upsertBlock replaces an existing pointer block or appends one, so calling it
// repeatedly is stable.
func upsertBlock(doc string) string {
	bi := strings.Index(doc, pointerBegin)
	ei := strings.Index(doc, pointerEnd)
	if bi >= 0 && ei > bi {
		before := doc[:bi]
		after := doc[ei+len(pointerEnd):]
		return before + PointerBlock + after
	}
	if strings.TrimSpace(doc) == "" {
		return PointerBlock + "\n"
	}
	return strings.TrimRight(doc, "\n") + "\n\n" + PointerBlock + "\n"
}

// removeBlock deletes the pointer block and collapses the blank lines that
// surrounded it, leaving the rest of the file intact.
func removeBlock(doc string) string {
	bi := strings.Index(doc, pointerBegin)
	ei := strings.Index(doc, pointerEnd)
	if bi < 0 || ei <= bi {
		return doc
	}
	before := strings.TrimRight(doc[:bi], "\n")
	after := strings.TrimLeft(doc[ei+len(pointerEnd):], "\n")
	switch {
	case before == "" && after == "":
		return ""
	case before == "":
		return after
	case after == "":
		return before + "\n"
	default:
		return before + "\n\n" + after
	}
}

func lookupAgent(id string) (agentDef, bool) {
	for _, d := range agentDefs() {
		if d.id == id {
			return d, true
		}
	}
	return agentDef{}, false
}

// configHome is the XDG config root, derived from ConfigPath so the fallback
// logic lives in one place (paths.go).
func configHome() string {
	return filepath.Dir(filepath.Dir(ConfigPath()))
}

func dirExists(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

func fileHasBlock(p string) bool {
	b, err := os.ReadFile(p)
	if err != nil {
		return false
	}
	s := string(b)
	return strings.Contains(s, pointerBegin) && strings.Contains(s, pointerEnd)
}

func readFileOrEmpty(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return string(b)
}

// tildeAbbrev renders an absolute home path as ~/... for display.
func tildeAbbrev(p string) string {
	h := home()
	if p == h {
		return "~"
	}
	if strings.HasPrefix(p, h+string(os.PathSeparator)) {
		return "~" + p[len(h):]
	}
	return p
}
