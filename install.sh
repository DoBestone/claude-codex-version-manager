#!/usr/bin/env bash
set -euo pipefail

REPO="${CVM_REPO:-DoBestone/claude-codex-version-manager}"
CVM_DIR="${CVM_DIR:-$HOME/.cvm}"
CVM_NPM_PACKAGE="@anthropic-ai/claude-code"
CVM_CODEX_NPM_PACKAGE="@openai/codex"
GLOBAL_PREFIX="${CVM_GLOBAL_PREFIX:-/usr/local}"
GLOBAL_SHARE_DIR="${CVM_GLOBAL_SHARE_DIR:-$GLOBAL_PREFIX/share/cvm}"
GLOBAL_BIN_DIR="${CVM_GLOBAL_BIN_DIR:-$GLOBAL_PREFIX/bin}"
GLOBAL_PROFILE="${CVM_GLOBAL_PROFILE:-/etc/profile.d/cvm.sh}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/src/cvm.sh"
START_MARKER="# >>> cvm >>>"
END_MARKER="# <<< cvm <<<"
GLOBAL_INSTALL=false
WRAPPER_COMMANDS=(
  cvm
  claude-auto claude-v claude-latest claude-versions claude-clean claude-update
  claude-detect claude-config
  claude-install claude-current claude-uninstall claude-remove
  claude-v-l claude-l-l claude-v-a claude-l-a claude-v-r claude-l-r
  codex-auto codex-v codex-v-a codex-l-a codex-v-l codex-l-l codex-v-r codex-l-r
  codex-latest codex-versions codex-clean codex-update codex-detect codex-config
  codex-install codex-current
  codex-uninstall codex-remove
)

write_wrapper() {
  local wrapper_path="$1"
  cat > "$wrapper_path" <<EOF
#!/usr/bin/env bash
# CVM_WRAPPER=1
set -e
source "$INSTALL_FILE"
command_name="\$(basename "\$0")"

if [[ "\$command_name" =~ ^claude-auto-([0-9]+\\.[0-9]+\\.[0-9]+)$ ]]; then
  cvm_use "\${BASH_REMATCH[1]}" --permission-mode bypassPermissions "\$@"
elif [[ "\$command_name" =~ ^claude-([0-9]+\\.[0-9]+\\.[0-9]+)$ ]]; then
  cvm_use "\${BASH_REMATCH[1]}" "\$@"
elif [[ "\$command_name" =~ ^codex-auto-([0-9]+\\.[0-9]+\\.[0-9]+)$ ]]; then
  _cvm_codex_use "\${BASH_REMATCH[1]}" --dangerously-bypass-approvals-and-sandbox "\$@"
elif [[ "\$command_name" =~ ^codex-([0-9]+\\.[0-9]+\\.[0-9]+)$ ]]; then
  _cvm_codex_use "\${BASH_REMATCH[1]}" "\$@"
else
  "\$command_name" "\$@"
fi
EOF
  chmod 0755 "$wrapper_path"
}

install_version_wrappers() {
  local package_name="$1"
  local command_prefix="$2"
  local auto_prefix="$3"
  local versions_json

  case "$command_prefix" in
    claude) versions_json="${CVM_TEST_CLAUDE_VERSIONS:-}" ;;
    codex) versions_json="${CVM_TEST_CODEX_VERSIONS:-}" ;;
  esac

  if [[ -z "${versions_json:-}" ]]; then
    versions_json=$(npm view "$package_name" versions --json --registry="${CVM_REGISTRY:-https://registry.npmjs.org}" 2>/dev/null) || return 0
  fi

  printf '%s' "$versions_json" | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const parsed = JSON.parse(input);
  const versions = Array.isArray(parsed) ? parsed : [parsed];
  versions
    .filter(version => /^\d+\.\d+\.\d+$/.test(version))
    .forEach(version => console.log(version));
});
' | while IFS= read -r version; do
    write_wrapper "$GLOBAL_BIN_DIR/${command_prefix}-${version}"
    write_wrapper "$GLOBAL_BIN_DIR/${auto_prefix}-${version}"
  done
}

if [[ "${1:-}" == "--global" ]]; then
  GLOBAL_INSTALL=true
elif [[ "${1:-}" == "--user" ]]; then
  GLOBAL_INSTALL=false
elif [[ -n "${1:-}" ]]; then
  printf '用法: %s [--global|--user]\n' "$0" >&2
  exit 1
elif [[ "${CVM_GLOBAL:-}" == "1" ]]; then
  GLOBAL_INSTALL=true
elif [[ "$(id -u)" == "0" && "${CVM_GLOBAL:-}" != "0" ]]; then
  GLOBAL_INSTALL=true
fi

default_shell_rc() {
  if [[ -n "${CVM_SHELL_RC:-}" ]]; then
    printf '%s\n' "$CVM_SHELL_RC"
    return 0
  fi

  case "$(basename "${SHELL:-}")" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash) printf '%s\n' "$HOME/.bashrc" ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

case "${CVM_TEST_UNAME:-$(uname -s)}" in
  Darwin|Linux|CYGWIN*|MINGW*|MSYS*) ;;
  *)
    printf 'CVM 当前自动安装器支持 macOS、Linux 和 Windows Git Bash/MSYS/Cygwin。\n' >&2
    exit 1
    ;;
esac

SHELL_RC="$(default_shell_rc)"
INSTALL_FILE="$CVM_DIR/cvm.sh"
# shellcheck disable=SC2016
SOURCE_LINE='[ -s "$HOME/.cvm/cvm.sh" ] && source "$HOME/.cvm/cvm.sh"'

if $GLOBAL_INSTALL; then
  INSTALL_FILE="$GLOBAL_SHARE_DIR/cvm.sh"
  SHELL_RC="$GLOBAL_PROFILE"
  SOURCE_LINE="[ -s \"$INSTALL_FILE\" ] && source \"$INSTALL_FILE\""
fi

for command_name in curl node npm bash; do
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
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$SOURCE_FILE"
fi

mkdir -p "$(dirname "$INSTALL_FILE")"
if [[ -f "$INSTALL_FILE" ]]; then
  cp "$INSTALL_FILE" "$INSTALL_FILE.bak"
fi
cp "$SOURCE_FILE" "$INSTALL_FILE"
chmod 0644 "$INSTALL_FILE"
mkdir -p "$CVM_DIR"
touch "$CVM_DIR/pins"

mkdir -p "$(dirname "$SHELL_RC")"
touch "$SHELL_RC"
cp "$SHELL_RC" "$SHELL_RC.cvm.bak"

node - "$SHELL_RC" "$START_MARKER" "$END_MARKER" "$SOURCE_LINE" <<'JS'
const fs = require("fs");
const [path, start, end, sourceLine] = process.argv.slice(2);
const text = fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
const sourceLines = new Set([
  '[ -s "$HOME/.cvm/cvm.sh" ] && source "$HOME/.cvm/cvm.sh"',
  '[ -s "$HOME/.cvm/cvm.sh" ] && . "$HOME/.cvm/cvm.sh"',
  '[ -s "/usr/local/share/cvm/cvm.sh" ] && source "/usr/local/share/cvm/cvm.sh"',
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
  sourceLine,
  end,
  "",
);
fs.writeFileSync(path, result.join("\n"));
JS

if $GLOBAL_INSTALL; then
  mkdir -p "$GLOBAL_BIN_DIR"
  for command_name in "${WRAPPER_COMMANDS[@]}"; do
    write_wrapper "$GLOBAL_BIN_DIR/$command_name"
  done
  install_version_wrappers "$CVM_NPM_PACKAGE" claude claude-auto
  install_version_wrappers "$CVM_CODEX_NPM_PACKAGE" codex codex-auto
fi

printf '\nCVM 安装完成。\n'
if $GLOBAL_INSTALL; then
  printf '  安装模式: 全局\n'
  printf '  管理脚本: %s\n' "$INSTALL_FILE"
  printf '  命令目录: %s\n' "$GLOBAL_BIN_DIR"
  printf '  Shell 加载: source %s\n' "$SHELL_RC"
else
  printf '  安装模式: 当前用户\n'
  printf '  加载环境: source %s\n' "$SHELL_RC"
fi
printf '  环境检查: cvm doctor\n'
printf '  Claude:   claude-l-a\n'
printf '  Codex:    codex-l-a\n\n'
