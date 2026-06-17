#!/usr/bin/env bash
set -euo pipefail

CVM_DIR="${CVM_DIR:-$HOME/.cvm}"
PURGE=false

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

SHELL_RC="$(default_shell_rc)"

if [[ "${1:-}" == "--purge" ]]; then
  PURGE=true
elif [[ -n "${1:-}" ]]; then
  printf '用法: %s [--purge]\n' "$0" >&2
  exit 1
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
  rm -rf "$CVM_DIR"
  printf 'CVM 及全部版本数据已删除。\n'
else
  rm -f "$CVM_DIR/cvm.sh" "$CVM_DIR/cvm.sh.bak"
  printf 'CVM 脚本已卸载，版本数据保留在 %s。\n' "$CVM_DIR"
fi

printf '请重开终端或执行: source %s\n' "$SHELL_RC"
