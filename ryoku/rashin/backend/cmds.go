package main

import "errors"

// Thin verb wrappers. Logic lives in the file named after the concern
// (vault.go, index.go, agents.go, server.go, setup.go); these stay thin so
// main.go never changes shape.

var errNotBuilt = errors.New("not implemented yet")

func cmdServe(ifEnabled bool) error { return errNotBuilt }

func cmdIndex() error { return errNotBuilt }

func cmdSetup() error { return errNotBuilt }

func cmdWire(agent string) error { return errNotBuilt }

func cmdUnwire(agent string) error { return errNotBuilt }

func cmdStatus(asJSON bool) error { return errNotBuilt }

func cmdEnable() error { return errNotBuilt }

func cmdDisable() error { return errNotBuilt }
