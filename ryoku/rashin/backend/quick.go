package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// quick.go is the fast lane for launcher asks: a fabric-style pattern (one
// terse system prompt + the vault's generated maps) sent as ONE direct
// chat-completions call on the same model connection hermes is configured
// with. No Python spawn, no agent loop, no tool schemas: most questions come
// back in a second or two. Questions that actually need tools escalate to the
// real hermes session (the model answers a sentinel instead).

const toolsSentinel = "TOOLS_REQUIRED"

const quickPattern = `You are Rashin, the resident agent of this Ryoku (Arch Linux, Hyprland) machine, answering a quick ask from the launcher.

Rules:
- Reply with just the answer: one or two sentences, or a tight list. No preamble, no follow-up questions, no markdown headers.
- The machine map below is current and trustworthy; prefer it over guessing.
- If the request requires running commands, browsing the live web, reading files beyond the map, summarizing external media, or generating files or images, reply with exactly TOOLS_REQUIRED and nothing else.`

// quickTarget is a resolved direct model connection.
type quickTarget struct {
	BaseURL string
	Key     string
	Model   string
	Label   string // provider:model for logs and the dashboard
}

// quickProviders maps hermes provider ids to openai-compatible endpoints.
var quickProviders = map[string]struct {
	base   string
	keyEnv string
}{
	"openrouter": {"https://openrouter.ai/api/v1", "OPENROUTER_API_KEY"},
	"openai":     {"https://api.openai.com/v1", "OPENAI_API_KEY"},
	"groq":       {"https://api.groq.com/openai/v1", "GROQ_API_KEY"},
	"ollama":     {"http://127.0.0.1:11434/v1", "OLLAMA_API_KEY"},
}

// hermesEnvValue reads one key from ~/.hermes/.env (process env wins).
func hermesEnvValue(key string) string {
	if key == "" {
		return ""
	}
	if v := os.Getenv(key); v != "" {
		return v
	}
	b, err := os.ReadFile(filepath.Join(home(), ".hermes", ".env"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "#") {
			continue
		}
		if v, ok := strings.CutPrefix(line, key+"="); ok {
			return strings.Trim(strings.TrimSpace(v), `"'`)
		}
	}
	return ""
}

// isLocalURL: keyless endpoints (ollama and friends) are fine on loopback.
func isLocalURL(u string) bool {
	return strings.Contains(u, "127.0.0.1") || strings.Contains(u, "localhost")
}

// resolveQuickTarget picks the fast lane's model connection: the rashin.json
// quick overrides first, else hermes's own configured provider when it speaks
// plain chat-completions. OAuth backends (openai-codex) and native anthropic
// cannot be called directly, so they report unavailable and asks take the
// session lane.
func resolveQuickTarget(cfg Config) (quickTarget, error) {
	provider, model, _ := hermesModel()

	t := quickTarget{Model: cfg.Quick.Model, BaseURL: cfg.Quick.BaseURL}
	if t.Model == "" {
		t.Model = model
	}
	keyEnv := cfg.Quick.KeyEnv

	if t.BaseURL == "" {
		if p, ok := quickProviders[provider]; ok {
			t.BaseURL = p.base
			if keyEnv == "" {
				keyEnv = p.keyEnv
			}
		}
	}
	if t.BaseURL == "" {
		return t, fmt.Errorf("provider %q has no direct endpoint; quick asks use the hermes session", provider)
	}
	if strings.Contains(t.BaseURL, "chatgpt.com") || strings.Contains(t.BaseURL, "anthropic.com") {
		return t, fmt.Errorf("provider %q is not directly callable; quick asks use the hermes session", provider)
	}
	if t.Model == "" {
		return t, fmt.Errorf("no model configured")
	}
	t.Key = hermesEnvValue(keyEnv)
	if t.Key == "" && !isLocalURL(t.BaseURL) {
		return t, fmt.Errorf("no API key in ~/.hermes/.env (%s); quick asks use the hermes session", keyEnv)
	}
	t.Label = provider + ":" + t.Model
	if cfg.Quick.Model != "" {
		t.Label = "quick:" + t.Model
	}
	return t, nil
}

// vaultQuickContext inlines the generated maps (fence bodies only) as the
// pattern's knowledge. Small by construction; capped defensively.
func vaultQuickContext() string {
	var b strings.Builder
	for _, name := range []string{"system.md", "desktop.md", "user.md"} {
		raw, err := ReadVaultFile(name)
		if err != nil {
			continue
		}
		body := string(raw)
		if bi := strings.Index(body, vaultFenceBegin); bi >= 0 {
			if ei := strings.Index(body, vaultFenceEnd); ei > bi {
				body = body[bi+len(vaultFenceBegin) : ei]
			}
		}
		body = strings.TrimSpace(body)
		if len(body) > 8*1024 {
			body = body[:8*1024]
		}
		fmt.Fprintf(&b, "## %s\n%s\n\n", name, body)
	}
	return b.String()
}

// quickComplete streams one chat completion. onDelta fires per content chunk
// (after the sentinel has been ruled out); the full answer is returned.
func quickComplete(ctx context.Context, t quickTarget, question string, onDelta func(string)) (string, error) {
	payload := map[string]any{
		"model":  t.Model,
		"stream": true,
		"messages": []map[string]string{
			{"role": "system", "content": quickPattern + "\n\n# The machine map\n\n" + vaultQuickContext()},
			{"role": "user", "content": question},
		},
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		strings.TrimRight(t.BaseURL, "/")+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if t.Key != "" {
		req.Header.Set("Authorization", "Bearer "+t.Key)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := readCapped(resp, 300)
		return "", fmt.Errorf("model endpoint %d: %s", resp.StatusCode, msg)
	}

	var answer strings.Builder
	held := true // buffer the head until it cannot be the sentinel
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 64*1024), 4<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "[DONE]" {
			break
		}
		var chunk struct {
			Choices []struct {
				Delta struct {
					Content string `json:"content"`
				} `json:"delta"`
			} `json:"choices"`
		}
		if json.Unmarshal([]byte(data), &chunk) != nil || len(chunk.Choices) == 0 {
			continue
		}
		delta := chunk.Choices[0].Delta.Content
		if delta == "" {
			continue
		}
		answer.WriteString(delta)
		if held {
			head := strings.TrimSpace(answer.String())
			if strings.HasPrefix(toolsSentinel, head) || strings.HasPrefix(head, toolsSentinel) {
				continue // still possibly (or definitely) the sentinel
			}
			held = false
			if onDelta != nil {
				onDelta(answer.String())
			}
			continue
		}
		if onDelta != nil {
			onDelta(delta)
		}
	}
	out := strings.TrimSpace(answer.String())
	if strings.HasPrefix(out, toolsSentinel) {
		return "", errNeedsTools
	}
	if out == "" {
		return "", fmt.Errorf("empty answer")
	}
	return out, nil
}

var errNeedsTools = fmt.Errorf("needs tools")

func readCapped(resp *http.Response, n int) (string, error) {
	buf := make([]byte, n)
	m, err := resp.Body.Read(buf)
	return strings.TrimSpace(string(buf[:m])), err
}

// warmHermes spawns the shared session at daemon start, so neither the
// dashboard's first message nor a session-lane ask pays the Python cold
// start. Costs hermes's resident memory from boot; that is the point of an
// enabled agent OS.
func (h *chatHub) warm() {
	if !HermesStatus().Configured {
		return
	}
	h.mu.Lock()
	h.ensureConnLocked()
	h.mu.Unlock()
}

// quickTime bounds the fast lane; escalation needs time for real model calls.
const quickTimeout = 75 * time.Second
