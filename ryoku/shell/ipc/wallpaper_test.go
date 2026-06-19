package main

import "testing"

func TestPickTransitionNeverRepeats(t *testing.T) {
	d := &daemon{}
	prev := -1
	for i := 0; i < 1000; i++ {
		if args := d.pickTransition(); args == nil {
			t.Fatal("pickTransition returned nil with presets defined")
		}
		if d.lastTransition == prev {
			t.Fatalf("transition %d repeated back-to-back", d.lastTransition)
		}
		prev = d.lastTransition
	}
}

func TestPresetsShareOneSpeed(t *testing.T) {
	// Every transition must run at the shared speed: no preset may carry its own
	// --transition-duration or --transition-fps (showWallpaper appends the shared
	// values), so they all stay in lockstep.
	for _, p := range transitionPresets {
		for _, a := range p.args {
			if a == "--transition-duration" || a == "--transition-fps" {
				t.Fatalf("preset %q sets %s itself; speed must stay shared", p.name, a)
			}
		}
	}
}
