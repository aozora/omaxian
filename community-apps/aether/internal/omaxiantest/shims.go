// Package omaxiantest helps tests that fake the Omarchy CLI.
//
// Upstream tests fake the `omarchy` group dispatcher and assert its
// arguments ("theme set aether"). Omaxian has no dispatcher, so Aether calls
// omarchy-theme-set / omarchy-theme-bg-set instead. CLIShims writes those
// next to the fake dispatcher, forwarding to it with the dispatcher's
// arguments, so the upstream assertions stay as they are.
package omaxiantest

import (
	"os"
	"path/filepath"
	"testing"
)

var shims = map[string]string{
	"omarchy-theme-set":    "theme set",
	"omarchy-theme-bg-set": "theme bg set",
}

// CLIShims writes the omarchy-* commands Aether runs into dir. Each runs
// dir/omarchy with the matching dispatcher subcommand. Tests often set PATH
// to dir alone, so the shims use no external commands.
func CLIShims(t *testing.T, dir string) {
	t.Helper()
	for name, subcommand := range shims {
		script := "#!/bin/sh\nexec \"${0%/*}/omarchy\" " + subcommand + " \"$@\"\n"
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
}
