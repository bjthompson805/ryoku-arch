package main

import (
	"bufio"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

// ask.go is the launcher's one-shot CLI: it POSTs the question to the running
// daemon's /api/ask and pipes the streamed marker lines straight to stdout.
// The daemon does the thinking (fast lane or hermes session) and records the
// conversation in the shared transcript, so "continue in dashboard" opens the
// very conversation this started.
//
// stdout protocol (one marker per line):
//   @working <label>   what the agent is doing right now
//   @perm <title>      a permission is waiting (answer it in the dashboard)
//   @answer <json>     {"text":"...","images":["/abs.png"]} final answer
//   @error <message>   terminal failure

// quickPreamble rides in front of session-lane questions so the model answers
// tersely. The transcript records the RAW question; only hermes sees this.
const quickPreamble = "[quick ask from the launcher: reply with just the answer, " +
	"one or two sentences or a tight list, no preamble, no follow-up questions] "

func cmdAsk(question string) error {
	question = strings.TrimSpace(question)
	if question == "" {
		return fmt.Errorf("usage: ryoku-rashin ask <question>")
	}
	cfg := LoadConfig()
	if !pingDaemon(cfg.Port) {
		emitAsk("error", "rashin is not running; enable it in Ryoku Settings, Advanced, Rashin")
		os.Exit(1)
	}

	client := http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Post(fmt.Sprintf(
		"http://127.0.0.1:%d/api/ask?q=%s", cfg.Port, url.QueryEscape(question)), "", nil)
	if err != nil {
		emitAsk("error", "cannot reach the daemon: "+err.Error())
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		emitAsk("error", fmt.Sprintf("daemon answered %d", resp.StatusCode))
		os.Exit(1)
	}
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 64*1024), 4<<20)
	for sc.Scan() {
		fmt.Println(sc.Text())
	}
	return nil
}

type askAnswer struct {
	Text   string   `json:"text"`
	Images []string `json:"images,omitempty"`
}

var imagePathRe = regexp.MustCompile(`(?:~|/)[^\s"'` + "`" + `)\]]*\.(?:png|jpe?g|webp|gif)`)

// extractImages pulls existing image files out of the answer text, so the
// launcher can preview what image_gen (or a screenshot tool) just produced.
func extractImages(text string) []string {
	var out []string
	seen := map[string]bool{}
	for _, m := range imagePathRe.FindAllString(text, 6) {
		p := m
		if strings.HasPrefix(p, "~") {
			p = home() + p[1:]
		}
		if seen[p] || !fileExists(p) {
			continue
		}
		seen[p] = true
		out = append(out, p)
	}
	return out
}

func emitAsk(kind, detail string) {
	fmt.Println("@" + kind + " " + strings.ReplaceAll(detail, "\n", " "))
}
