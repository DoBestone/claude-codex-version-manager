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

mkdir -p "$TEMP_HOME/.claude" "$TEMP_HOME/.codex"
printf '%s\n' '{"apiKey":"sk-test-secret","oauth":{"accessToken":"oauth-secret"},"account":{"email":"user@example.com"}}' > "$TEMP_HOME/.claude/settings.json"
printf '%s\n' '{"projects":{"/tmp/noise":{"lastSessionFirstPrompt":"do not show"}},"model":"claude-test-model"}' > "$TEMP_HOME/.claude.json"
printf '%s\n' 'api_key = "codex-secret"' > "$TEMP_HOME/.codex/config.toml"
printf '%s\n' '{"OPENAI_API_KEY":"codex-json-secret","account":{"email":"user@example.com"}}' > "$TEMP_HOME/.codex/auth.json"

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
  cvm help | grep -q "用法"
  printf "0\n" | cvm >/dev/null
  claude_config="$(cvm config claude)"
  codex_config="$(cvm config codex)"
  printf "%s" "$claude_config" | grep -q "API URL ANTHROPIC_BASE_URL"
  printf "%s" "$codex_config" | grep -q "API URL OPENAI_BASE_URL"
  claude_env_config="$(ANTHROPIC_BASE_URL="https://anthropic.example/v1" ANTHROPIC_API_KEY="sk-ant-test" cvm config claude)"
  codex_env_config="$(OPENAI_BASE_URL="https://openai.example/v1" cvm config codex)"
  printf "%s" "$claude_env_config" | grep -q "https://anthropic.example/v1"
  printf "%s" "$codex_env_config" | grep -q "https://openai.example/v1"
  printf "%s" "$claude_env_config" | grep -q "API Key ANTHROPIC_API_KEY: string(len=11) <redacted>"
  ANTHROPIC_API_KEY="sk-ant-test" cvm config claude --show-secrets | grep -q "API Key ANTHROPIC_API_KEY: sk-ant-test"
  cvm config set claude api-url "https://managed-anthropic.example/v1" >/dev/null
  [[ "$ANTHROPIC_BASE_URL" == "https://managed-anthropic.example/v1" ]]
  grep -q "ANTHROPIC_BASE_URL=.*https://managed-anthropic.example/v1" "$HOME/.cvm/env"
  bash --noprofile --norc -c "CVM_DIR=\"$HOME/.cvm\"; source \"$HOME/.cvm/cvm.sh\"; [[ \"\$ANTHROPIC_BASE_URL\" == \"https://managed-anthropic.example/v1\" ]]"
  cvm config clear claude api-url >/dev/null
  [[ -z "${ANTHROPIC_BASE_URL:-}" ]]
  if grep -q "ANTHROPIC_BASE_URL" "$HOME/.cvm/env"; then
    exit 1
  fi
  cvm profile add claude work "https://profile-anthropic.example/v1" "sk-profile" "claude-profile-model" "socks5://127.0.0.1:7890" >/dev/null
  cvm profile list claude | grep -q "work"
  cvm profile list claude | grep -q "1)"
  cvm profile use claude work >/dev/null
  [[ "$ANTHROPIC_BASE_URL" == "https://profile-anthropic.example/v1" ]]
  [[ "$ANTHROPIC_API_KEY" == "sk-profile" ]]
  [[ "$ANTHROPIC_MODEL" == "claude-profile-model" ]]
  [[ "$HTTPS_PROXY" == "socks5://127.0.0.1:7890" ]]
  cvm profile delete claude work >/dev/null
  if cvm profile list claude | grep -q "work"; then
    exit 1
  fi
  printf "2\n2\nmenu-codex\nhttps://menu-openai.example/v1\nsk-menu\ngpt-menu-test\nhttp://127.0.0.1:7890\n5\n1\n0\n0\n" | cvm menu >/dev/null 2>&1
  unset OPENAI_MODEL
  source "$HOME/.cvm/env"
  [[ "$OPENAI_MODEL" == "gpt-menu-test" ]]
  [[ "$OPENAI_BASE_URL" == "https://menu-openai.example/v1" ]]
  [[ "$OPENAI_API_KEY" == "sk-menu" ]]
  [[ "$HTTPS_PROXY" == "http://127.0.0.1:7890" ]]
  printf "%s" "$claude_config" | grep -q "apiKey: string(len=14) <redacted>"
  printf "%s" "$claude_config" | grep -q "oauth.accessToken: string(len=12) <redacted>"
  printf "%s" "$claude_config" | grep -q "model: claude-test-model"
  if printf "%s" "$claude_config" | grep -q "lastSessionFirstPrompt"; then
    exit 1
  fi
  printf "%s" "$codex_config" | grep -q "api_key = <redacted>"
  printf "%s" "$codex_config" | grep -q "OPENAI_API_KEY: string(len=17) <redacted>"
  if printf "%s" "$claude_config" | grep -q "sk-test-secret"; then
    exit 1
  fi
  if printf "%s" "$codex_config" | grep -q "codex-json-secret"; then
    exit 1
  fi
  cvm config claude --show-secrets | grep -q "sk-test-secret"
  cvm config codex --show-secrets | grep -q "codex-json-secret"
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
