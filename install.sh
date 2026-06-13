#!/usr/bin/env bash
set -euo pipefail

REPO="${CVM_REPO:-DoBestone/claude-codex-version-manager}"
CVM_DIR="${CVM_DIR:-$HOME/.cvm}"
SHELL_RC="${CVM_SHELL_RC:-$HOME/.zshrc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/src/cvm.sh"
START_MARKER="# >>> cvm >>>"
END_MARKER="# <<< cvm <<<"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'CVM 当前自动安装器仅支持 macOS。\n' >&2
  exit 1
fi

for command_name in curl node npm zsh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf '缺少依赖: %s\n' "$command_name" >&2
    exit 1
  fi
done

temp_file=""
cleanup() {
  if [[ -n "$temp_file" ]]; then
    rm -f "$temp_file"
  fi
  return 0
}
trap cleanup EXIT

if [[ ! -f "$SOURCE_FILE" ]]; then
  temp_file="$(mktemp)"
  curl --fail --location --silent --show-error \
    "https://raw.githubusercontent.com/${REPO}/main/src/cvm.sh" \
    --output "$temp_file"
  SOURCE_FILE="$temp_file"
fi

bash -n "$SOURCE_FILE"
zsh -n "$SOURCE_FILE"

mkdir -p "$CVM_DIR"
if [[ -f "$CVM_DIR/cvm.sh" ]]; then
  cp "$CVM_DIR/cvm.sh" "$CVM_DIR/cvm.sh.bak"
fi
cp "$SOURCE_FILE" "$CVM_DIR/cvm.sh"
chmod 0644 "$CVM_DIR/cvm.sh"
touch "$CVM_DIR/pins"

mkdir -p "$(dirname "$SHELL_RC")"
touch "$SHELL_RC"
cp "$SHELL_RC" "$SHELL_RC.cvm.bak"

node - "$SHELL_RC" "$START_MARKER" "$END_MARKER" <<'JS'
const fs = require("fs");
const [path, start, end] = process.argv.slice(2);
const text = fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
const sourceLines = new Set([
  '[ -s "$HOME/.cvm/cvm.sh" ] && source "$HOME/.cvm/cvm.sh"',
  '[ -s "$HOME/.cvm/cvm.sh" ] && . "$HOME/.cvm/cvm.sh"',
]);
const result = [];
let inside = false;
for (const line of text.split(/\r?\n/)) {
  if (line === start) {
    inside = true;
    continue;
  }
  if (inside && line === end) {
    inside = false;
    continue;
  }
  if (!inside && !sourceLines.has(line.trim())) result.push(line);
}
while (result.length && !result.at(-1).trim()) result.pop();
result.push(
  "",
  start,
  '[ -s "$HOME/.cvm/cvm.sh" ] && source "$HOME/.cvm/cvm.sh"',
  end,
  "",
);
fs.writeFileSync(path, result.join("\n"));
JS

printf '\nCVM 安装完成。\n'
printf '  加载环境: source %s\n' "$SHELL_RC"
printf '  环境检查: cvm doctor\n'
printf '  Claude:   claude-l-a\n'
printf '  Codex:    codex-l-a\n\n'
