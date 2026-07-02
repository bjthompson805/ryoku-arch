package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Config struct {
	Enabled bool `json:"enabled"`
	Port    int  `json:"port"`
	// Quick overrides the launcher fast lane's model connection. Empty means
	// derive it from hermes's own provider config.
	Quick struct {
		Model   string `json:"model,omitempty"`
		BaseURL string `json:"baseUrl,omitempty"`
		KeyEnv  string `json:"keyEnv,omitempty"`
	} `json:"quick,omitzero"`
}

func defaultConfig() Config {
	return Config{Enabled: false, Port: 3600}
}

func LoadConfig() Config {
	c := defaultConfig()
	b, err := os.ReadFile(ConfigPath())
	if err != nil {
		return c
	}
	if json.Unmarshal(b, &c) != nil {
		return defaultConfig()
	}
	if c.Port <= 0 || c.Port > 65535 {
		c.Port = 3600
	}
	return c
}

func SaveConfig(c Config) error {
	p := ConfigPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}
