# shellcheck shell=bash
# Files install.sh copies into ~/.local/share/omarchy-local-ai.
# bin/build stages the same set for the pre-built tarball. One list.

ENGINE_FILES=(
  agent_local.py
  omaxian_units.py
  omarchy-local-ai
  catalog.toml
  best.toml
  recipes
  runtimes
  reviews
  measurements
  docs
  README.md
  LICENSE
)
