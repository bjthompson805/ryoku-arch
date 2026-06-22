package main

import (
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

// TestPrompterInterop proves the prompter interoperates with the real
// gnome-keyring-daemon: it registers as the system prompter (auto-answering with
// a known password), then creates a password-protected keyring, locks it, and
// unlocks it through the Secret Service. gnome-keyring only accepts the unlock if
// the password our secret exchange decrypts matches, so a green run is end-to-end
// proof of the DH/HKDF/AES wire format against the real implementation.
//
// It touches the live keyring daemon and creates (then deletes) a throwaway
// collection, so it is gated behind RYOKU_KEYRING_INTEROP=1 and skipped in CI and
// ordinary `go test`.
func TestPrompterInterop(t *testing.T) {
	if os.Getenv("RYOKU_KEYRING_INTEROP") != "1" {
		t.Skip("set RYOKU_KEYRING_INTEROP=1 to run the live gnome-keyring interop test")
	}

	const pw = "ryoku-interop-pw-\U0001F510" // a non-ASCII secret exercises utf-8

	// The prompter and the Secret Service client must look like distinct peers,
	// so they use separate bus connections.
	pConn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatalf("prompter bus: %v", err)
	}
	defer pConn.Close()

	p := &prompter{conn: pConn, prompts: map[dbus.ObjectPath]*promptSession{}}
	var attempts int32
	p.onShow = func(id int, ptype string, props map[string]interface{}) {
		// Answer with the known password, but stop after a few tries so a wrong
		// decryption fails the assertion instead of looping forever.
		if atomic.AddInt32(&attempts, 1) > 3 {
			go p.respond(id, "cancel", false, "")
			return
		}
		go p.respond(id, "continue", false, pw)
	}
	if err := pConn.Export(p, dbus.ObjectPath(prompterPath), prompterIface); err != nil {
		t.Fatalf("export prompter: %v", err)
	}
	reply, err := pConn.RequestName(prompterName, dbus.NameFlagReplaceExisting|dbus.NameFlagDoNotQueue)
	if err != nil {
		t.Fatalf("request name: %v", err)
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		t.Skipf("%s already owned; another prompter is running", prompterName)
	}

	cConn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatalf("client bus: %v", err)
	}
	defer cConn.Close()
	secrets := cConn.Object("org.freedesktop.secrets", "/org/freedesktop/secrets")

	// Create a password-protected collection (a "new keyring password" prompt).
	var collPath, promptPath dbus.ObjectPath
	props := map[string]dbus.Variant{
		"org.freedesktop.Secret.Collection.Label": dbus.MakeVariant("ryoku-interop-test"),
	}
	if err := secrets.Call("org.freedesktop.Secret.Service.CreateCollection", 0, props, "").
		Store(&collPath, &promptPath); err != nil {
		t.Fatalf("CreateCollection: %v", err)
	}
	if collPath == "/" {
		res, dismissed := runSecretPrompt(t, cConn, promptPath)
		if dismissed {
			t.Fatal("create-collection prompt was dismissed")
		}
		collPath = res.Value().(dbus.ObjectPath)
	}
	if collPath == "/" || collPath == "" {
		t.Fatal("no collection created")
	}
	defer deleteCollection(t, cConn, collPath)

	// Lock it, then unlock it (a password prompt) so the round trip is exercised.
	var locked []dbus.ObjectPath
	if err := secrets.Call("org.freedesktop.Secret.Service.Lock", 0, []dbus.ObjectPath{collPath}).
		Store(&locked, &promptPath); err != nil {
		t.Fatalf("Lock: %v", err)
	}
	if promptPath != "/" {
		runSecretPrompt(t, cConn, promptPath)
	}

	coll := cConn.Object("org.freedesktop.secrets", collPath)
	if v, err := coll.GetProperty("org.freedesktop.Secret.Collection.Locked"); err == nil {
		if isLocked, ok := v.Value().(bool); ok && !isLocked {
			t.Fatal("collection did not lock; cannot exercise the unlock prompt")
		}
	}

	var unlocked []dbus.ObjectPath
	if err := secrets.Call("org.freedesktop.Secret.Service.Unlock", 0, []dbus.ObjectPath{collPath}).
		Store(&unlocked, &promptPath); err != nil {
		t.Fatalf("Unlock: %v", err)
	}
	if promptPath != "/" {
		_, dismissed := runSecretPrompt(t, cConn, promptPath)
		if dismissed {
			t.Fatal("unlock prompt was dismissed")
		}
	}

	v, err := coll.GetProperty("org.freedesktop.Secret.Collection.Locked")
	if err != nil {
		t.Fatalf("read Locked property: %v", err)
	}
	if isLocked, _ := v.Value().(bool); isLocked {
		t.Fatal("collection still locked: gnome-keyring rejected the decrypted password (wire format mismatch)")
	}
	t.Logf("gnome-keyring accepted the password decrypted via the island exchange (attempts=%d)", attempts)
}

// runSecretPrompt drives an org.freedesktop.Secret.Prompt and waits for its
// Completed signal, returning the result and whether it was dismissed.
func runSecretPrompt(t *testing.T, conn *dbus.Conn, promptPath dbus.ObjectPath) (dbus.Variant, bool) {
	t.Helper()
	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(promptPath),
		dbus.WithMatchInterface("org.freedesktop.Secret.Prompt"),
		dbus.WithMatchMember("Completed"),
	); err != nil {
		t.Fatalf("match signal: %v", err)
	}
	ch := make(chan *dbus.Signal, 8)
	conn.Signal(ch)
	defer conn.RemoveSignal(ch)

	if call := conn.Object("org.freedesktop.secrets", promptPath).
		Call("org.freedesktop.Secret.Prompt.Prompt", 0, ""); call.Err != nil {
		t.Fatalf("Prompt: %v", call.Err)
	}
	for {
		select {
		case sig := <-ch:
			if sig.Path == promptPath && sig.Name == "org.freedesktop.Secret.Prompt.Completed" && len(sig.Body) == 2 {
				dismissed, _ := sig.Body[0].(bool)
				return sig.Body[1].(dbus.Variant), dismissed
			}
		case <-time.After(20 * time.Second):
			t.Fatal("secret prompt timed out")
		}
	}
}

func deleteCollection(t *testing.T, conn *dbus.Conn, collPath dbus.ObjectPath) {
	t.Helper()
	var promptPath dbus.ObjectPath
	if err := conn.Object("org.freedesktop.secrets", collPath).
		Call("org.freedesktop.Secret.Collection.Delete", 0).Store(&promptPath); err != nil {
		t.Logf("cleanup: delete collection: %v", err)
		return
	}
	if promptPath != "/" {
		runSecretPrompt(t, conn, promptPath)
	}
}
