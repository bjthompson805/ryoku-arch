package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
)

// Thin verb wrappers over the concern files (vault.go, index.go, agents.go,
// hermes.go, server.go, setup.go) so main.go never changes shape.

func cmdIndex() error {
	if err := EnsureVault(); err != nil {
		return err
	}
	return Reindex()
}

func cmdWire(agent string) error {
	if err := EnsureVault(); err != nil {
		return err
	}
	if agent == "" {
		n := WireAll()
		if err := wireHermesIfPresent(); err == nil {
			n++
		}
		fmt.Printf("wired %d agents\n", n)
		return nil
	}
	if agent == "hermes" {
		return WireHermesMemory()
	}
	return Wire(agent)
}

func cmdUnwire(agent string) error {
	if agent == "" {
		for _, a := range DetectAgents() {
			if a.Wired {
				if err := Unwire(a.ID); err != nil {
					return err
				}
			}
		}
		return nil
	}
	return Unwire(agent)
}

func cmdStatus(asJSON bool) error {
	st := BuildStatus(LoadConfig())
	if asJSON {
		return json.NewEncoder(os.Stdout).Encode(st)
	}
	running := "stopped"
	if st.Running {
		running = fmt.Sprintf("running on http://127.0.0.1:%d", st.Port)
	}
	fmt.Printf("daemon:  %s (enabled: %v)\n", running, st.Enabled)
	fmt.Printf("vault:   %s (%d files)\n", st.Vault.Path, st.Vault.Files)
	fmt.Printf("hermes:  installed=%v configured=%v wired=%v %s\n",
		st.Hermes.Installed, st.Hermes.Configured, st.Hermes.Wired, st.Hermes.Version)
	for _, a := range st.Agents {
		fmt.Printf("agent:   %-10s present=%-5v wired=%-5v %s\n", a.ID, a.Present, a.Wired, a.File)
	}
	return nil
}

func wireHermesIfPresent() error {
	if _, ok := FindHermes(); !ok {
		return errors.New("hermes not installed")
	}
	return WireHermesMemory()
}
