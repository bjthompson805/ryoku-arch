package main

// `ryoku-shell spotify <auth|search|play|pause|next|previous>` is the launcher's
// Spotify Web API client: PKCE OAuth (public client, no secret), token stored
// under XDG_STATE, refreshed on demand. Catalog search complements the MPRIS
// provider, which already controls the running Spotify client; the Web API adds
// what MPRIS cannot do (search the catalog, queue arbitrary tracks). Playback
// commands need Spotify Premium and an active device.

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	spotifyAuthURL  = "https://accounts.spotify.com/authorize"
	spotifyTokenURL = "https://accounts.spotify.com/api/token"
	spotifyAPIBase  = "https://api.spotify.com/v1"
	spotifyScopes   = "user-read-playback-state user-modify-playback-state playlist-read-private user-library-read user-library-modify"
	refreshSkew     = 60 // seconds before expiry a token is treated as stale
	callbackPort    = 15298
)

type spotifyToken struct {
	ClientID     string `json:"client_id"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	Expiry       int64  `json:"expiry"` // unix seconds
}

type spotifyTrack struct {
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"`
	URI      string `json:"uri"`
	ID       string `json:"id"`
}

// pkceChallenge is base64url-no-pad SHA-256 of the verifier (RFC 7636 S256).
func pkceChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func pkceVerifier() string {
	b := make([]byte, 64)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// tokenValid reports whether tok can be used at time `now` without refreshing.
func tokenValid(tok spotifyToken, now int64) bool {
	return tok.AccessToken != "" && now < tok.Expiry-refreshSkew
}

func spotifyTokenPath() string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(base, "ryoku", "spotify-token.json")
}

func loadSpotifyToken() (spotifyToken, error) {
	var tok spotifyToken
	data, err := os.ReadFile(spotifyTokenPath())
	if err != nil {
		return tok, err
	}
	err = json.Unmarshal(data, &tok)
	return tok, err
}

func saveSpotifyToken(tok spotifyToken) error {
	path := spotifyTokenPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(tok)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

// parseSearchTracks maps a Spotify /search track payload to launcher rows.
func parseSearchTracks(body []byte) ([]spotifyTrack, error) {
	var resp struct {
		Tracks struct {
			Items []struct {
				Name    string `json:"name"`
				URI     string `json:"uri"`
				ID      string `json:"id"`
				Artists []struct {
					Name string `json:"name"`
				} `json:"artists"`
				Album struct {
					Name string `json:"name"`
				} `json:"album"`
			} `json:"items"`
		} `json:"tracks"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, err
	}
	out := make([]spotifyTrack, 0, len(resp.Tracks.Items))
	for _, it := range resp.Tracks.Items {
		names := make([]string, 0, len(it.Artists))
		for _, a := range it.Artists {
			names = append(names, a.Name)
		}
		out = append(out, spotifyTrack{
			Title:    it.Name,
			Subtitle: strings.Join(names, ", ") + " \u00b7 " + it.Album.Name,
			URI:      it.URI,
			ID:       it.ID,
		})
	}
	return out, nil
}

func httpClient() *http.Client { return &http.Client{Timeout: 12 * time.Second} }

// ensureToken returns a fresh access token, refreshing if the stored one is stale.
func ensureToken() (spotifyToken, error) {
	tok, err := loadSpotifyToken()
	if err != nil {
		return tok, fmt.Errorf("not authenticated (run `ryoku-shell spotify auth <client-id>`)")
	}
	if tokenValid(tok, time.Now().Unix()) {
		return tok, nil
	}
	if tok.RefreshToken == "" {
		return tok, fmt.Errorf("session expired; re-run `ryoku-shell spotify auth`")
	}
	form := url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {tok.RefreshToken},
		"client_id":     {tok.ClientID},
	}
	resp, err := httpClient().PostForm(spotifyTokenURL, form)
	if err != nil {
		return tok, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var tr struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tr); err != nil || tr.AccessToken == "" {
		return tok, fmt.Errorf("token refresh failed: %s", strings.TrimSpace(string(body)))
	}
	tok.AccessToken = tr.AccessToken
	if tr.RefreshToken != "" {
		tok.RefreshToken = tr.RefreshToken
	}
	tok.Expiry = time.Now().Unix() + tr.ExpiresIn
	_ = saveSpotifyToken(tok)
	return tok, nil
}

func spotifyAPI(method, path, accessToken string, body io.Reader) ([]byte, int, error) {
	req, err := http.NewRequest(method, spotifyAPIBase+path, body)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := httpClient().Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	out, _ := io.ReadAll(resp.Body)
	return out, resp.StatusCode, nil
}

// runSpotify is the `ryoku-shell spotify ...` entry point (client-local, never
// forwarded to the daemon).
func runSpotify(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: ryoku-shell spotify <auth|search|play|pause|next|previous>")
		return 2
	}
	switch args[0] {
	case "auth":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: ryoku-shell spotify auth <client-id>")
			return 2
		}
		if err := spotifyAuth(args[1]); err != nil {
			fmt.Fprintln(os.Stderr, "spotify auth:", err)
			return 1
		}
		return 0
	case "search":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: ryoku-shell spotify search <query>")
			return 2
		}
		if err := spotifySearch(strings.Join(args[1:], " ")); err != nil {
			fmt.Fprintln(os.Stderr, "spotify search:", err)
			return 1
		}
		return 0
	case "play", "pause", "next", "previous":
		if err := spotifyControl(args[0], args[1:]); err != nil {
			fmt.Fprintln(os.Stderr, "spotify "+args[0]+":", err)
			return 1
		}
		return 0
	default:
		fmt.Fprintln(os.Stderr, "spotify: unknown command:", args[0])
		return 2
	}
}

func spotifySearch(query string) error {
	tok, err := ensureToken()
	if err != nil {
		return err
	}
	q := url.Values{"q": {query}, "type": {"track"}, "limit": {"20"}}
	body, status, err := spotifyAPI("GET", "/search?"+q.Encode(), tok.AccessToken, nil)
	if err != nil {
		return err
	}
	if status != http.StatusOK {
		return fmt.Errorf("api status %d: %s", status, strings.TrimSpace(string(body)))
	}
	tracks, err := parseSearchTracks(body)
	if err != nil {
		return err
	}
	out, _ := json.Marshal(struct {
		Schema int            `json:"schema"`
		Data   []spotifyTrack `json:"data"`
	}{Schema: 1, Data: tracks})
	fmt.Println(string(out))
	return nil
}

func spotifyControl(action string, args []string) error {
	tok, err := ensureToken()
	if err != nil {
		return err
	}
	var status int
	var body []byte
	switch action {
	case "play":
		var payload io.Reader
		path := "/me/player/play"
		if len(args) > 0 {
			b, _ := json.Marshal(map[string][]string{"uris": {args[0]}})
			payload = strings.NewReader(string(b))
		}
		body, status, err = spotifyAPI("PUT", path, tok.AccessToken, payload)
	case "pause":
		body, status, err = spotifyAPI("PUT", "/me/player/pause", tok.AccessToken, nil)
	case "next":
		body, status, err = spotifyAPI("POST", "/me/player/next", tok.AccessToken, nil)
	case "previous":
		body, status, err = spotifyAPI("POST", "/me/player/previous", tok.AccessToken, nil)
	}
	if err != nil {
		return err
	}
	if status >= 400 {
		return fmt.Errorf("api status %d: %s", status, strings.TrimSpace(string(body)))
	}
	return nil
}

// spotifyAuth runs the PKCE flow: open the consent URL, catch the redirect on a
// loopback server, exchange the code for tokens, and store them.
func spotifyAuth(clientID string) error {
	verifier := pkceVerifier()
	challenge := pkceChallenge(verifier)
	redirect := fmt.Sprintf("http://127.0.0.1:%d/callback", callbackPort)

	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", callbackPort))
	if err != nil {
		return fmt.Errorf("loopback port %d busy: %w", callbackPort, err)
	}
	defer listener.Close()

	authURL := spotifyAuthURL + "?" + url.Values{
		"client_id":             {clientID},
		"response_type":         {"code"},
		"redirect_uri":          {redirect},
		"code_challenge_method": {"S256"},
		"code_challenge":        {challenge},
		"scope":                 {spotifyScopes},
	}.Encode()

	fmt.Println("Opening Spotify authorization in your browser...")
	fmt.Println("If it does not open, visit:\n" + authURL)
	_ = exec.Command("xdg-open", authURL).Start()

	codeCh := make(chan string, 1)
	srv := &http.Server{}
	http.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		code := r.URL.Query().Get("code")
		if code == "" {
			fmt.Fprint(w, "Authorization failed. You can close this tab.")
			codeCh <- ""
			return
		}
		fmt.Fprint(w, "Ryoku is connected to Spotify. You can close this tab.")
		codeCh <- code
	})
	go srv.Serve(listener)
	defer srv.Close()

	var code string
	select {
	case code = <-codeCh:
	case <-time.After(3 * time.Minute):
		return fmt.Errorf("timed out waiting for authorization")
	}
	if code == "" {
		return fmt.Errorf("no authorization code received")
	}

	form := url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {code},
		"redirect_uri":  {redirect},
		"client_id":     {clientID},
		"code_verifier": {verifier},
	}
	resp, err := httpClient().PostForm(spotifyTokenURL, form)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var tr struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tr); err != nil || tr.AccessToken == "" {
		return fmt.Errorf("token exchange failed: %s", strings.TrimSpace(string(body)))
	}
	tok := spotifyToken{
		ClientID:     clientID,
		AccessToken:  tr.AccessToken,
		RefreshToken: tr.RefreshToken,
		Expiry:       time.Now().Unix() + tr.ExpiresIn,
	}
	if err := saveSpotifyToken(tok); err != nil {
		return err
	}
	fmt.Println("Spotify connected.")
	return nil
}
