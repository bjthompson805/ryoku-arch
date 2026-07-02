package main

import (
	"fmt"
	"os"
)

const usage = `ryoku-rashin: the Ryoku agent OS daemon

usage: ryoku-rashin <command>

  serve [--if-enabled]   run the dashboard and agent bridge on 127.0.0.1
  index                  regenerate the vault maps (system, desktop, packages, repo, user)
  repo-index <root> [out]  build the Ryoku source map from a checkout (build/deploy time)
  setup                  one-click Hermes install, onboarding, and wiring
  wire [agent]           apply vault pointers (all detected agents, or one)
  unwire [agent]         remove vault pointers
  status [--json]        report daemon, vault, hermes, and wiring state
  enable                 gate autostart on and start the daemon
  disable                gate autostart off and stop the daemon
`

func main() {
	if len(os.Args) < 2 {
		fmt.Print(usage)
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "serve":
		ifEnabled := len(os.Args) > 2 && os.Args[2] == "--if-enabled"
		err = cmdServe(ifEnabled)
	case "index":
		err = cmdIndex()
	case "repo-index":
		err = cmdRepoIndex(argOr(2, ""), argOr(3, ""))
	case "setup":
		err = cmdSetup()
	case "wire":
		err = cmdWire(argOr(2, ""))
	case "unwire":
		err = cmdUnwire(argOr(2, ""))
	case "status":
		err = cmdStatus(len(os.Args) > 2 && os.Args[2] == "--json")
	case "enable":
		err = cmdEnable()
	case "disable":
		err = cmdDisable()
	default:
		fmt.Print(usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-rashin:", err)
		os.Exit(1)
	}
}

func argOr(i int, def string) string {
	if len(os.Args) > i {
		return os.Args[i]
	}
	return def
}
