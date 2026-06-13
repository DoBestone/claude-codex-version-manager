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
  [[ "$(cvm version)" == "cvm v1.5.0" ]]
  for command_name in \
    cvm claude-auto claude-v claude-l-a claude-v-a claude-l-l claude-v-l \
    claude-l-r claude-v-r claude-install claude-current claude-uninstall \
    claude-remove codex-auto codex-v codex-l-a codex-v-a codex-l-l \
    codex-v-l codex-l-r codex-v-r codex-install codex-current \
    codex-uninstall codex-remove; do
    whence -w "$command_name" >/dev/null
  done

  functions command_not_found_handler | grep -q "claude-auto-"
  functions command_not_found_handler | grep -q "codex-auto-"

  cvm_install() { [[ "$1" == "2.1.177" ]]; }
  cvm_uninstall() { [[ "$1" == "2.1.177" ]]; }
  _cvm_codex_install_version() { [[ "$1" == "0.139.0" ]]; }
  _cvm_codex_uninstall() { [[ "$1" == "0.139.0" ]]; }
  claude-install 2.1.177
  claude-uninstall 2.1.177
  claude-remove 2.1.177
  codex-install 0.139.0
  codex-uninstall 0.139.0
  codex-remove 0.139.0
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
if grep -q '# >>> cvm >>>' "$TEMP_HOME/.zshrc"; then
  printf '卸载后仍残留 shell 初始化配置。\n' >&2
  exit 1
fi

printf 'Smoke tests passed.\n'
