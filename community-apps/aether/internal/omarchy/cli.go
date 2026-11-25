package omarchy

import (
	"fmt"

	"aether/internal/platform"
)

// Omaxian (Omarchy for Debian + i3) has no `omarchy` group dispatcher: each
// subcommand is its own omarchy-* binary on PATH. Aether only needs these.
var cliCommands = map[string]string{
	"theme set":    "omarchy-theme-set",
	"theme bg set": "omarchy-theme-bg-set",
}

// cliProbe is the command whose presence means the Omarchy CLI is installed.
const cliProbe = "omarchy-theme-set"

// runCLI runs `omarchy <subcommand> <arg>` as its omarchy-* binary.
func runCLI(extraEnv map[string]string, subcommand, arg string) (string, error) {
	name, ok := cliCommands[subcommand]
	if !ok {
		return "", fmt.Errorf("unsupported omarchy command %q", subcommand)
	}
	return platform.RunSyncEnv(extraEnv, name, arg)
}
