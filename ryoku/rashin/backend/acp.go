package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"sync"
	"sync/atomic"
)

// acp.go speaks the Agent Client Protocol: newline-delimited JSON-RPC 2.0
// over the hermes acp child's stdio. One conn drives one hermes session whose
// cwd is the vault, so terminal hermes and the dashboard share one memory.

type PermOption struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Kind string `json:"kind"`
}

// AcpEvent is the translated stream ws.go forwards to the dashboard.
type AcpEvent struct {
	Type       string // state | agent_text | agent_thought | tool | permission | turn_end
	State      string
	Err        string
	Text       string
	ToolID     string
	ToolTitle  string
	ToolKind   string
	ToolStatus string
	RequestID  string
	PermTitle  string
	Options    []PermOption
	StopReason string
}

type rpcMsg struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      *int64          `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type acpConn struct {
	in     io.Writer
	closer io.Closer

	writeMu sync.Mutex
	nextID  atomic.Int64

	mu        sync.Mutex
	pending   map[int64]chan rpcMsg
	sessionID string
	closed    bool

	events chan AcpEvent
}

func newACPConn(in io.Writer, out io.Reader, closer io.Closer) *acpConn {
	c := &acpConn{
		in:      in,
		closer:  closer,
		pending: map[int64]chan rpcMsg{},
		events:  make(chan AcpEvent, 256),
	}
	go c.readLoop(out)
	return c
}

func (c *acpConn) Events() <-chan AcpEvent { return c.events }

func (c *acpConn) send(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err = c.in.Write(append(b, '\n'))
	return err
}

func (c *acpConn) request(method string, params any) (json.RawMessage, error) {
	id := c.nextID.Add(1)
	ch := make(chan rpcMsg, 1)
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil, errors.New("acp connection closed")
	}
	c.pending[id] = ch
	c.mu.Unlock()

	p, err := json.Marshal(params)
	if err != nil {
		return nil, err
	}
	if err := c.send(rpcMsg{JSONRPC: "2.0", ID: &id, Method: method, Params: p}); err != nil {
		return nil, err
	}
	resp, ok := <-ch
	if !ok {
		return nil, errors.New("acp connection closed")
	}
	if resp.Error != nil {
		return nil, fmt.Errorf("acp %s: %s", method, resp.Error.Message)
	}
	return resp.Result, nil
}

func (c *acpConn) notify(method string, params any) {
	p, err := json.Marshal(params)
	if err != nil {
		return
	}
	_ = c.send(rpcMsg{JSONRPC: "2.0", Method: method, Params: p})
}

func (c *acpConn) respond(id int64, result any) {
	r, err := json.Marshal(result)
	if err != nil {
		return
	}
	_ = c.send(rpcMsg{JSONRPC: "2.0", ID: &id, Result: r})
}

// Initialize performs the ACP handshake and opens the vault session.
func (c *acpConn) Initialize(vault string) error {
	_, err := c.request("initialize", map[string]any{
		"protocolVersion": 1,
		"clientCapabilities": map[string]any{
			"fs": map[string]bool{"readTextFile": false, "writeTextFile": false},
		},
	})
	if err != nil {
		return err
	}
	res, err := c.request("session/new", map[string]any{
		"cwd":        vault,
		"mcpServers": []any{},
	})
	if err != nil {
		return err
	}
	var out struct {
		SessionID string `json:"sessionId"`
	}
	if err := json.Unmarshal(res, &out); err != nil || out.SessionID == "" {
		return errors.New("acp session/new: no sessionId")
	}
	c.mu.Lock()
	c.sessionID = out.SessionID
	c.mu.Unlock()
	return nil
}

// Prompt runs one user turn; the turn_end event carries the stop reason.
func (c *acpConn) Prompt(text string) {
	c.mu.Lock()
	sid := c.sessionID
	c.mu.Unlock()
	go func() {
		res, err := c.request("session/prompt", map[string]any{
			"sessionId": sid,
			"prompt":    []map[string]string{{"type": "text", "text": text}},
		})
		if err != nil {
			c.emit(AcpEvent{Type: "state", State: "dead", Err: err.Error()})
			return
		}
		var out struct {
			StopReason string `json:"stopReason"`
		}
		_ = json.Unmarshal(res, &out)
		c.emit(AcpEvent{Type: "turn_end", StopReason: out.StopReason})
	}()
}

func (c *acpConn) Cancel() {
	c.mu.Lock()
	sid := c.sessionID
	c.mu.Unlock()
	c.notify("session/cancel", map[string]string{"sessionId": sid})
}

// RespondPermission answers an inbound session/request_permission request.
func (c *acpConn) RespondPermission(requestID int64, optionID string) {
	outcome := map[string]any{"outcome": "cancelled"}
	if optionID != "" {
		outcome = map[string]any{"outcome": "selected", "optionId": optionID}
	}
	c.respond(requestID, map[string]any{"outcome": outcome})
}

func (c *acpConn) Close() {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	c.closed = true
	for id, ch := range c.pending {
		close(ch)
		delete(c.pending, id)
	}
	c.mu.Unlock()
	if c.closer != nil {
		_ = c.closer.Close()
	}
}

func (c *acpConn) emit(ev AcpEvent) {
	select {
	case c.events <- ev:
	default: // a stalled dashboard must not wedge the agent
	}
}

func (c *acpConn) readLoop(out io.Reader) {
	sc := bufio.NewScanner(out)
	sc.Buffer(make([]byte, 64*1024), 16*1024*1024)
	for sc.Scan() {
		line := sc.Bytes()
		if len(line) == 0 {
			continue
		}
		var msg rpcMsg
		if json.Unmarshal(line, &msg) != nil {
			continue
		}
		switch {
		case msg.ID != nil && msg.Method != "":
			c.handleAgentRequest(msg)
		case msg.ID != nil:
			c.mu.Lock()
			ch, ok := c.pending[*msg.ID]
			if ok {
				delete(c.pending, *msg.ID)
			}
			c.mu.Unlock()
			if ok {
				ch <- msg
			}
		case msg.Method == "session/update":
			c.handleUpdate(msg.Params)
		}
	}
	c.mu.Lock()
	c.closed = true
	for id, ch := range c.pending {
		close(ch)
		delete(c.pending, id)
	}
	c.mu.Unlock()
	c.emit(AcpEvent{Type: "state", State: "dead"})
	close(c.events)
}

func (c *acpConn) handleAgentRequest(msg rpcMsg) {
	switch msg.Method {
	case "session/request_permission":
		var p struct {
			ToolCall struct {
				Title string `json:"title"`
			} `json:"toolCall"`
			Options []struct {
				OptionID string `json:"optionId"`
				Name     string `json:"name"`
				Kind     string `json:"kind"`
			} `json:"options"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		opts := make([]PermOption, 0, len(p.Options))
		for _, o := range p.Options {
			opts = append(opts, PermOption{ID: o.OptionID, Name: o.Name, Kind: o.Kind})
		}
		c.emit(AcpEvent{
			Type:      "permission",
			RequestID: fmt.Sprint(*msg.ID),
			PermTitle: p.ToolCall.Title,
			Options:   opts,
		})
	default:
		// Unknown inbound request: JSON-RPC method-not-found keeps the child sane.
		id := *msg.ID
		_ = c.send(rpcMsg{JSONRPC: "2.0", ID: &id, Error: &rpcError{Code: -32601, Message: "method not found"}})
	}
}

func (c *acpConn) handleUpdate(params json.RawMessage) {
	var p struct {
		Update struct {
			SessionUpdate string `json:"sessionUpdate"`
			Content       struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
			ToolCallID string `json:"toolCallId"`
			Title      string `json:"title"`
			Kind       string `json:"kind"`
			Status     string `json:"status"`
		} `json:"update"`
	}
	if json.Unmarshal(params, &p) != nil {
		return
	}
	u := p.Update
	switch u.SessionUpdate {
	case "agent_message_chunk":
		c.emit(AcpEvent{Type: "agent_text", Text: u.Content.Text})
	case "agent_thought_chunk":
		c.emit(AcpEvent{Type: "agent_thought", Text: u.Content.Text})
	case "tool_call", "tool_call_update":
		status := u.Status
		if status == "" {
			status = "pending"
		}
		c.emit(AcpEvent{
			Type: "tool", ToolID: u.ToolCallID, ToolTitle: u.Title,
			ToolKind: u.Kind, ToolStatus: status,
		})
	}
}

// startACP spawns hermes acp with the vault as its working directory.
func startACP(vault string) (*acpConn, error) {
	bin, ok := FindHermes()
	if !ok {
		return nil, errors.New("hermes not installed")
	}
	cmd := exec.Command(bin, "acp")
	cmd.Dir = vault
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	cmd.Stderr = nil // hermes logs to stderr; silence rather than corrupt ndjson
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	c := newACPConn(stdin, stdout, stdin)
	go func() { _ = cmd.Wait() }()
	return c, nil
}
