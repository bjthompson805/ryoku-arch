package main

import "testing"

// PKCE challenge must be the base64url-no-pad SHA-256 of the verifier, the value
// Spotify checks the token exchange against. A known vector pins it (RFC 7636
// appendix B uses this verifier/challenge pair).
func TestPkceChallenge(t *testing.T) {
	verifier := "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	want := "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
	got := pkceChallenge(verifier)
	if got != want {
		t.Fatalf("pkceChallenge = %q, want %q", got, want)
	}
}

// Search parsing turns Spotify's track JSON into launcher rows: title, a
// "artist - album" subtitle, the play URI, and the id.
func TestParseSearchTracks(t *testing.T) {
	body := []byte(`{"tracks":{"items":[
		{"name":"Song A","uri":"spotify:track:1","id":"1",
		 "artists":[{"name":"Artist A"},{"name":"Feat B"}],
		 "album":{"name":"Album A"}},
		{"name":"Song B","uri":"spotify:track:2","id":"2",
		 "artists":[{"name":"Artist B"}],"album":{"name":"Album B"}}
	]}}`)
	tracks, err := parseSearchTracks(body)
	if err != nil {
		t.Fatalf("parseSearchTracks error: %v", err)
	}
	if len(tracks) != 2 {
		t.Fatalf("got %d tracks, want 2", len(tracks))
	}
	if tracks[0].Title != "Song A" {
		t.Fatalf("track 0 title = %q", tracks[0].Title)
	}
	if tracks[0].Subtitle != "Artist A, Feat B \u00b7 Album A" {
		t.Fatalf("track 0 subtitle = %q", tracks[0].Subtitle)
	}
	if tracks[0].URI != "spotify:track:1" || tracks[0].ID != "1" {
		t.Fatalf("track 0 uri/id = %q/%q", tracks[0].URI, tracks[0].ID)
	}
}

func TestParseSearchTracksEmpty(t *testing.T) {
	tracks, err := parseSearchTracks([]byte(`{"tracks":{"items":[]}}`))
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if len(tracks) != 0 {
		t.Fatalf("got %d tracks, want 0", len(tracks))
	}
}

// A token is valid only with an access token that isn't past its expiry (with a
// refresh skew so a near-expiry token is treated as stale).
func TestTokenValid(t *testing.T) {
	if !tokenValid(spotifyToken{AccessToken: "x", Expiry: 1000}, 900) {
		t.Fatal("token well before expiry should be valid")
	}
	if tokenValid(spotifyToken{AccessToken: "x", Expiry: 1000}, 995) {
		t.Fatal("token within refresh skew should be stale")
	}
	if tokenValid(spotifyToken{AccessToken: "", Expiry: 9999}, 0) {
		t.Fatal("empty access token is never valid")
	}
}
