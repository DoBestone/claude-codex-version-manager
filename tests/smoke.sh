#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT

bash -n "$ROOT/src/cvm.sh"
zsh -n "$ROOT/src/cvm.sh"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm" \
CVM_SHELL_RC="$TEMP_HOME/.zshrc" \
bash "$ROOT/install.sh"

HOME="$TEMP_HOME" CVM_DIR="$TEMP_HOME/.cvm" zsh -f -c '
  source "$HOME/.cvm/cvm.sh"
  [[ "$(cvm version)" == "cvm v1.4.0" ]]
  for command_name in \
    cvm claude-v claude-l-a claude-v-a claude-l-l claude-v-l \
    claude-l-r claude-v-r codex-v codex-l-a codex-v-a codex-l-l \
    codex-v-l codex-l-r codex-v-r; do
    whence -w "$command_name" >/dev/null
  done
'

grep -q '# >>> cvm >>>' "$TEMP_HOME/.zshrc"

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm" \
CVM_SHELL_RC="$TEMP_HOME/.zshrc" \
bash "$ROOT/install.sh"

[[ "$(grep -c '# >>> cvm >>>' "$TEMP_HOME/.zshrc")" -eq 1 ]]

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm" \
CVM_SHELL_RC="$TEMP_HOME/.zshrc" \
bash "$ROOT/uninstall.sh"

[[ ! -f "$TEMP_HOME/.cvm/cvm.sh" ]]
[[ -d "$TEMP_HOME/.cvm" ]]
! grep -q '# >>> cvm >>>' "$TEMP_HOME/.zshrc"

printf 'Smoke tests passed.\n'
