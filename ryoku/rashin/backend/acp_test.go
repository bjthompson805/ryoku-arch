package main

import (
	"bufio"
	"encoding/json"
	"io"
	"testing"
	"time"
)

// fakeAgent scripts the other end of the ACP wire: it reads client lines from
// r and writes agent lines to w, mimicking hermes acp closely enough to prove
// the handshake, streaming translation, permission round trip, and cancel.
type fakeAgent struct {
	lines chan rpcMsg
	w     io.Writer
	t     *testing.T
}

// read pops the next client frame. A dedicated goroutine drains the pipe so
// client writes never block on the synchronous io.Pipe (a real hermes stdin
// is OS-buffered; the fake must not be stricter than the real thing).
func (f *fakeAgent) read() rpcMsg {
	f.t.Helper()
	select {
	case m, ok := <-f.lines:
		if !ok {
			f.t.Fatal("fake agent: client closed early")
		}
		return m
	case <-time.After(3 * time.Second):
		f.t.Fatal("fake agent: timeout waiting for client frame")
	}
	return rpcMsg{}
}

func (f *fakeAgent) write(v any) {
	f.t.Helper()
	b, _ := json.Marshal(v)
	if _, err := f.w.Write(append(b, '\n')); err != nil {
		f.t.Fatalf("fake agent write: %v", err)
	}
}

func (f *fakeAgent) respond(id int64, result any) {
	r, _ := json.Marshal(result)
	f.write(rpcMsg{JSONRPC: "2.0", ID: &id, Result: r})
}

func (f *fakeAgent) update(session string, update map[string]any) {
	p, _ := json.Marshal(map[string]any{"sessionId": session, "update": update})
	f.write(rpcMsg{JSONRPC: "2.0", Method: "session/update", Params: p})
}

func newTestPair(t *testing.T) (*acpConn, *fakeAgent) {
	cr, cw := io.Pipe() // client -> agent
	ar, aw := io.Pipe() // agent -> client
	conn := newACPConn(cw, ar, cw)
	fa := &fakeAgent{lines: make(chan rpcMsg, 64), w: aw, t: t}
	go func() {
		sc := bufio.NewScanner(cr)
		for sc.Scan() {
			var m rpcMsg
			if json.Unmarshal(sc.Bytes(), &m) == nil {
				fa.lines <- m
			}
		}
		close(fa.lines)
	}()
	return conn, fa
}

func expectEvent(t *testing.T, ch <-chan AcpEvent, typ string) AcpEvent {
	t.Helper()
	select {
	case ev, ok := <-ch:
		if !ok {
			t.Fatalf("event channel closed waiting for %s", typ)
		}
		if ev.Type != typ {
			t.Fatalf("got event %q, want %q (%+v)", ev.Type, typ, ev)
		}
		return ev
	case <-time.After(3 * time.Second):
		t.Fatalf("timeout waiting for %s event", typ)
	}
	return AcpEvent{}
}

func TestACPHandshakePromptStreamPermissionCancel(t *testing.T) {
	conn, fa := newTestPair(t)
	defer conn.Close()

	done := make(chan error, 1)
	go func() { done <- conn.Initialize("/tmp/vault") }()

	init := fa.read()
	if init.Method != "initialize" {
		t.Fatalf("first request %q, want initialize", init.Method)
	}
	fa.respond(*init.ID, map[string]any{"protocolVersion": 1})

	newSess := fa.read()
	if newSess.Method != "session/new" {
		t.Fatalf("second request %q, want session/new", newSess.Method)
	}
	var np struct {
		Cwd string `json:"cwd"`
	}
	_ = json.Unmarshal(newSess.Params, &np)
	if np.Cwd != "/tmp/vault" {
		t.Fatalf("session cwd %q, want /tmp/vault", np.Cwd)
	}
	fa.respond(*newSess.ID, map[string]any{"sessionId": "s1"})

	if err := <-done; err != nil {
		t.Fatalf("Initialize: %v", err)
	}

	// One user turn with streaming chunks and a tool call.
	conn.Prompt("hello")
	prompt := fa.read()
	if prompt.Method != "session/prompt" {
		t.Fatalf("got %q, want session/prompt", prompt.Method)
	}
	fa.update("s1", map[string]any{
		"sessionUpdate": "agent_message_chunk",
		"content":       map[string]string{"type": "text", "text": "Hi "},
	})
	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call", "toolCallId": "t1",
		"title": "Reading system.md", "kind": "read", "status": "in_progress",
	})
	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
	})

	ev := expectEvent(t, conn.Events(), "agent_text")
	if ev.Text != "Hi " {
		t.Fatalf("chunk text %q", ev.Text)
	}
	ev = expectEvent(t, conn.Events(), "tool")
	if ev.ToolID != "t1" || ev.ToolStatus != "in_progress" {
		t.Fatalf("tool event %+v", ev)
	}
	ev = expectEvent(t, conn.Events(), "tool")
	if ev.ToolStatus != "completed" {
		t.Fatalf("tool update %+v", ev)
	}

	// Permission round trip: agent asks, client answers allow.
	permID := int64(77)
	pp, _ := json.Marshal(map[string]any{
		"sessionId": "s1",
		"toolCall":  map[string]string{"title": "Run ls"},
		"options": []map[string]string{
			{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
			{"optionId": "deny", "name": "Deny", "kind": "reject_once"},
		},
	})
	fa.write(rpcMsg{JSONRPC: "2.0", ID: &permID, Method: "session/request_permission", Params: pp})

	ev = expectEvent(t, conn.Events(), "permission")
	if ev.RequestID != "77" || len(ev.Options) != 2 || ev.PermTitle != "Run ls" {
		t.Fatalf("permission event %+v", ev)
	}
	conn.RespondPermission(77, "allow")
	permResp := fa.read()
	if permResp.ID == nil || *permResp.ID != 77 {
		t.Fatalf("permission response id %+v", permResp.ID)
	}
	var pr struct {
		Outcome struct {
			Outcome  string `json:"outcome"`
			OptionID string `json:"optionId"`
		} `json:"outcome"`
	}
	_ = json.Unmarshal(permResp.Result, &pr)
	if pr.Outcome.Outcome != "selected" || pr.Outcome.OptionID != "allow" {
		t.Fatalf("permission outcome %+v", pr)
	}

	// Turn end.
	fa.respond(*prompt.ID, map[string]any{"stopReason": "end_turn"})
	ev = expectEvent(t, conn.Events(), "turn_end")
	if ev.StopReason != "end_turn" {
		t.Fatalf("stop reason %q", ev.StopReason)
	}

	// Cancel is a notification.
	conn.Cancel()
	cancel := fa.read()
	if cancel.Method != "session/cancel" || cancel.ID != nil {
		t.Fatalf("cancel frame %+v", cancel)
	}
}

func TestACPDeadChildEmitsDeadState(t *testing.T) {
	cr, cw := io.Pipe()
	ar, aw := io.Pipe()
	conn := newACPConn(cw, ar, cw)
	_ = cr
	_ = aw.Close() // child dies immediately

	ev := expectEvent(t, conn.Events(), "state")
	if ev.State != "dead" {
		t.Fatalf("state %q, want dead", ev.State)
	}
}
