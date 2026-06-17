#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT

bash -n "$ROOT/src/cvm.sh"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/src/cvm.sh"
fi
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm" \
CVM_SHELL_RC="$TEMP_HOME/.bashrc" \
CVM_TEST_UNAME=Linux \
bash "$ROOT/install.sh"

HOME="$TEMP_HOME" CVM_DIR="$TEMP_HOME/.cvm" bash --noprofile --norc -c '
  set -e
  source "$HOME/.cvm/cvm.sh"
  [[ "$(cvm version)" == "cvm v1.5.0" ]]
  for command_name in \
    cvm claude-auto claude-v claude-l-a claude-v-a claude-l-l claude-v-l \
    claude-l-r claude-v-r claude-install claude-current claude-uninstall \
    claude-remove claude-detect claude-config codex-auto codex-v codex-l-a codex-v-a codex-l-l \
    codex-v-l codex-l-r codex-v-r codex-install codex-current \
    codex-uninstall codex-remove codex-detect codex-config; do
    type "$command_name" >/dev/null
  done

  cvm config claude >/dev/null
  cvm config codex >/dev/null
  cvm detect claude >/dev/null
  cvm detect codex >/dev/null

  cvm_install() { [[ "$1" == "2.1.177" ]]; }
  cvm_uninstall() { [[ "$1" == "2.1.177" ]]; }
  cvm_use() { [[ "$1" == "2.1.177" ]]; }
  _cvm_codex_install_version() { [[ "$1" == "0.139.0" ]]; }
  _cvm_codex_uninstall() { [[ "$1" == "0.139.0" ]]; }
  _cvm_codex_use() { [[ "$1" == "0.139.0" ]]; }
  claude-install 2.1.177
  claude-uninstall 2.1.177
  claude-remove 2.1.177
  command_not_found_handle claude-2.1.177
  command_not_found_handle claude-auto-2.1.177
  codex-install 0.139.0
  codex-uninstall 0.139.0
  codex-remove 0.139.0
  command_not_found_handle codex-0.139.0
  command_not_found_handle codex-auto-0.139.0

  uname() {
    case "$1" in
      -s) printf "Linux\n" ;;
      -m) printf "aarch64\n" ;;
    esac
  }
  [[ "$(_cvm_platform_package)" == "@anthropic-ai/claude-code-linux-arm64" ]]

  uname() {
    case "$1" in
      -s) printf "MINGW64_NT-10.0\n" ;;
      -m) printf "x86_64\n" ;;
    esac
  }
  [[ "$(_cvm_platform_package)" == "@anthropic-ai/claude-code-win32-x64" ]]
'

if command -v zsh >/dev/null 2>&1; then
  HOME="$TEMP_HOME" CVM_DIR="$TEMP_HOME/.cvm" zsh -f -c '
  source "$HOME/.cvm/cvm.sh"
  [[ "$(cvm version)" == "cvm v1.5.0" ]]
  for command_name in \
    cvm claude-auto claude-v claude-l-a claude-v-a claude-l-l claude-v-l \
    claude-l-r claude-v-r claude-install claude-current claude-uninstall \
    claude-remove claude-detect claude-config codex-auto codex-v codex-l-a codex-v-a codex-l-l \
    codex-v-l codex-l-r codex-v-r codex-install codex-current \
    codex-uninstall codex-remove codex-detect codex-config; do
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
fi

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm-global-data" \
CVM_GLOBAL_PREFIX="$TEMP_HOME/global" \
CVM_GLOBAL_PROFILE="$TEMP_HOME/profile.d/cvm.sh" \
CVM_TEST_CLAUDE_VERSIONS='["2.1.177"]' \
CVM_TEST_CODEX_VERSIONS='["0.139.0"]' \
CVM_TEST_UNAME=Linux \
bash "$ROOT/install.sh" --global

[[ "$("$TEMP_HOME/global/bin/cvm" version)" == "cvm v1.5.0" ]]
[[ -x "$TEMP_HOME/global/bin/claude-v-l" ]]
[[ -x "$TEMP_HOME/global/bin/claude-2.1.177" ]]
[[ -x "$TEMP_HOME/global/bin/claude-auto-2.1.177" ]]
[[ -x "$TEMP_HOME/global/bin/codex-0.139.0" ]]
[[ -x "$TEMP_HOME/global/bin/codex-auto-0.139.0" ]]
grep -q '# >>> cvm >>>' "$TEMP_HOME/profile.d/cvm.sh"

grep -q '# >>> cvm >>>' "$TEMP_HOME/.bashrc"

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm" \
CVM_SHELL_RC="$TEMP_HOME/.bashrc" \
CVM_TEST_UNAME=MINGW64_NT-10.0 \
bash "$ROOT/install.sh"

[[ "$(grep -c '# >>> cvm >>>' "$TEMP_HOME/.bashrc")" -eq 1 ]]

HOME="$TEMP_HOME" \
CVM_DIR="$TEMP_HOME/.cvm" \
CVM_SHELL_RC="$TEMP_HOME/.bashrc" \
bash "$ROOT/uninstall.sh"

[[ ! -f "$TEMP_HOME/.cvm/cvm.sh" ]]
[[ -d "$TEMP_HOME/.cvm" ]]
if grep -q '# >>> cvm >>>' "$TEMP_HOME/.bashrc"; then
  printf '卸载后仍残留 shell 初始化配置。\n' >&2
  exit 1
fi

printf 'Smoke tests passed.\n'
