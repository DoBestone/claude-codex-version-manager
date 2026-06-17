#!/usr/bin/env bash
set -euo pipefail

CVM_DIR="${CVM_DIR:-$HOME/.cvm}"
GLOBAL_PREFIX="${CVM_GLOBAL_PREFIX:-/usr/local}"
GLOBAL_SHARE_DIR="${CVM_GLOBAL_SHARE_DIR:-$GLOBAL_PREFIX/share/cvm}"
GLOBAL_BIN_DIR="${CVM_GLOBAL_BIN_DIR:-$GLOBAL_PREFIX/bin}"
GLOBAL_PROFILE="${CVM_GLOBAL_PROFILE:-/etc/profile.d/cvm.sh}"
PURGE=false
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=true ;;
    --global) GLOBAL_INSTALL=true ;;
    --user) GLOBAL_INSTALL=false ;;
    *)
      printf '用法: %s [--global|--user] [--purge]\n' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${CVM_GLOBAL:-}" == "1" ]]; then
  GLOBAL_INSTALL=true
elif [[ "$(id -u)" == "0" && "${CVM_GLOBAL:-}" != "0" ]]; then
  GLOBAL_INSTALL=true
fi

SHELL_RC="$(default_shell_rc)"
INSTALL_FILE="$CVM_DIR/cvm.sh"
if $GLOBAL_INSTALL; then
  SHELL_RC="$GLOBAL_PROFILE"
  INSTALL_FILE="$GLOBAL_SHARE_DIR/cvm.sh"
fi

if [[ -f "$SHELL_RC" ]]; then
  cp "$SHELL_RC" "$SHELL_RC.cvm-uninstall.bak"
  node - "$SHELL_RC" <<'JS'
const fs = require("fs");
const path = process.argv[2];
const result = [];
let inside = false;
for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
  if (line === "# >>> cvm >>>") {
    inside = true;
    continue;
  }
  if (inside && line === "# <<< cvm <<<") {
    inside = false;
    continue;
  }
  if (!inside) result.push(line);
}
fs.writeFileSync(path, `${result.join("\n").trimEnd()}\n`);
JS
fi

if $PURGE; then
  if $GLOBAL_INSTALL; then
    rm -rf "$GLOBAL_SHARE_DIR"
    rm -rf "$CVM_DIR"
    printf 'CVM 全局脚本及当前用户版本数据已删除。\n'
  else
    rm -rf "$CVM_DIR"
    printf 'CVM 及全部版本数据已删除。\n'
  fi
else
  rm -f "$INSTALL_FILE" "$INSTALL_FILE.bak"
  if $GLOBAL_INSTALL; then
    printf 'CVM 全局脚本已卸载，当前用户版本数据保留在 %s。\n' "$CVM_DIR"
  else
    printf 'CVM 脚本已卸载，版本数据保留在 %s。\n' "$CVM_DIR"
  fi
fi

if $GLOBAL_INSTALL; then
  for command_name in "${WRAPPER_COMMANDS[@]}"; do
    rm -f "$GLOBAL_BIN_DIR/$command_name"
  done
  for wrapper_path in "$GLOBAL_BIN_DIR"/claude-* "$GLOBAL_BIN_DIR"/codex-* "$GLOBAL_BIN_DIR"/cvm; do
    [[ -f "$wrapper_path" ]] || continue
    if grep -q '^# CVM_WRAPPER=1$' "$wrapper_path" 2>/dev/null; then
      rm -f "$wrapper_path"
    fi
  done
fi

printf '请重开终端或执行: source %s\n' "$SHELL_RC"
