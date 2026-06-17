package main

import "testing"

func segByMount(segs []part, mount string) (part, bool) {
	for _, s := range segs {
		if s.mount == mount {
			return s, true
		}
	}
	return part{}, false
}

func segByFS(segs []part, fs string) (part, bool) {
	for _, s := range segs {
		if s.fs == fs {
			return s, true
		}
	}
	return part{}, false
}

// Root is the rest of the disk after the ESP, and the swapfile is carved out of
// it, so usable root must shrink by exactly the swap size and no "free" segment
// should appear (the backend always gives root 100% of the remaining space).
func TestRootCarvesSwap(t *testing.T) {
	m := model{diskG: 1000, espG: 1, swapG: 16}
	if got := m.availRoot(); got != 999 {
		t.Fatalf("availRoot = %d, want 999", got)
	}
	root, ok := segByMount(m.layoutSegs(), "/")
	if !ok || root.size != 983 {
		t.Fatalf("root usable = %d (ok=%v), want 983 (999 - 16 swap)", root.size, ok)
	}
	if sw, ok := segByFS(m.layoutSegs(), "swap"); !ok || sw.size != 16 {
		t.Fatalf("swap segment = %d (ok=%v), want 16", sw.size, ok)
	}
	for _, s := range m.layoutSegs() {
		if s.status == "free" {
			t.Fatalf("unexpected free segment %+v", s)
		}
	}
}

// The reported bug: bumping swap must reduce the usable total.
func TestSwapReducesRoot(t *testing.T) {
	m := model{diskG: 1000, espG: 1, swapG: 16}
	before, _ := segByMount(m.layoutSegs(), "/")
	m.swapG = 32
	after, _ := segByMount(m.layoutSegs(), "/")
	if after.size >= before.size {
		t.Fatalf("root did not shrink when swap grew: %d -> %d", before.size, after.size)
	}
	if after.size != 967 {
		t.Fatalf("root = %d, want 967 (999 - 32)", after.size)
	}
}

// swapG = 0 means no swapfile, so no swap segment and root takes the whole rest.
func TestNoSwapNoSegment(t *testing.T) {
	m := model{diskG: 1000, espG: 1, swapG: 0}
	if _, ok := segByFS(m.layoutSegs(), "swap"); ok {
		t.Fatal("swap segment present with swapG=0")
	}
	root, _ := segByMount(m.layoutSegs(), "/")
	if root.size != 999 {
		t.Fatalf("root = %d, want 999", root.size)
	}
}

func TestSwapCeil(t *testing.T) {
	if got := (model{diskG: 1000, espG: 1}).swapCeil(); got != 64 {
		t.Fatalf("swapCeil big disk = %d, want 64", got)
	}
	if got := (model{diskG: 40, espG: 1}).swapCeil(); got != 31 {
		t.Fatalf("swapCeil small disk = %d, want 31 (39 - 8)", got)
	}
	if got := (model{diskG: 8, espG: 1}).swapCeil(); got != 0 {
		t.Fatalf("swapCeil tiny disk = %d, want 0 (never negative)", got)
	}
}

// Growing the ESP eats from the same pool, so an out-of-range swap is pulled back.
func TestESPBumpClampsSwap(t *testing.T) {
	m := model{diskG: 40, espG: 1, swapG: 30}
	m.setRow("esp", 4) // availRoot 36 -> swapCeil 28
	if m.swapG != 28 {
		t.Fatalf("swap after esp bump = %d, want 28", m.swapG)
	}
}
