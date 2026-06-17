#!/usr/bin/env bash
# ============================================================================
# CVM - Claude Code / Codex Version Manager
# A lightweight cross-platform version manager for Claude Code and OpenAI Codex CLI
# ============================================================================

CVM_VERSION="1.5.0"
CVM_DIR="${CVM_DIR:-$HOME/.cvm}"
CVM_REPO="${CVM_REPO:-DoBestone/claude-codex-version-manager}"
CVM_PINS_FILE="$CVM_DIR/pins"
CVM_NPM_PACKAGE="@anthropic-ai/claude-code"
CVM_VERSIONS_DIR="$CVM_DIR/versions"
CVM_CODEX_NPM_PACKAGE="@openai/codex"
CVM_CODEX_VERSIONS_DIR="$CVM_DIR/codex-versions"
CVM_REGISTRY="${CVM_REGISTRY:-https://registry.npmjs.org}"
CVM_ENV_FILE="${CVM_ENV_FILE:-$CVM_DIR/env}"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

if [[ -f "$CVM_ENV_FILE" ]]; then
  source "$CVM_ENV_FILE"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

_cvm_ensure_dir() {
  [[ -d "$CVM_DIR" ]] || mkdir -p "$CVM_DIR"
  [[ -d "$CVM_VERSIONS_DIR" ]] || mkdir -p "$CVM_VERSIONS_DIR"
  [[ -d "$CVM_CODEX_VERSIONS_DIR" ]] || mkdir -p "$CVM_CODEX_VERSIONS_DIR"
  [[ -f "$CVM_PINS_FILE" ]] || touch "$CVM_PINS_FILE"
}

_cvm_log() {
  echo -e "${GREEN}✔${NC} $1"
}

_cvm_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

_cvm_err() {
  echo -e "${RED}✖${NC} $1" >&2
}

_cvm_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

_cvm_check_npm() {
  if ! command -v npm &>/dev/null; then
    _cvm_err "npm 未安装。请先安装 Node.js: https://nodejs.org"
    return 1
  fi
}

_cvm_check_npx() {
  if ! command -v npx &>/dev/null; then
    _cvm_err "npx 未安装。请先安装 Node.js >= 14"
    return 1
  fi
}

# Get current globally installed version
_cvm_current_version() {
  if command -v claude &>/dev/null; then
    claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
  fi
}

# Check if a version exists on npm
_cvm_version_exists() {
  local ver="$1"
  [[ "$(npm view "${CVM_NPM_PACKAGE}@${ver}" version --registry="$CVM_REGISTRY" 2>/dev/null)" == "$ver" ]]
}

_cvm_package_exists() {
  local package_spec="$1"
  npm view "$package_spec" version --registry="$CVM_REGISTRY" &>/dev/null 2>&1
}

_cvm_version_entry() {
  local package_dir="$CVM_VERSIONS_DIR/$1/node_modules/$CVM_NPM_PACKAGE"
  local package_json="$package_dir/package.json"
  local bin_path
  bin_path=$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.claude" 2>/dev/null)
  [[ -n "$bin_path" ]] && echo "$package_dir/$bin_path"
}

_cvm_version_installed() {
  local ver="$1"
  local package_json="$CVM_VERSIONS_DIR/$ver/node_modules/$CVM_NPM_PACKAGE/package.json"
  local entry
  entry=$(_cvm_version_entry "$ver")
  [[ -n "$entry" ]] &&
    [[ -x "$entry" ]] &&
    [[ -f "$package_json" ]] &&
    [[ "$(node -p "require('$package_json').version" 2>/dev/null)" == "$ver" ]] &&
    [[ "$("$entry" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" == "$ver" ]]
}

_cvm_import_npx_cache() {
  local ver="$1"
  local install_dir="$CVM_VERSIONS_DIR/$ver"
  local temp_dir="$CVM_VERSIONS_DIR/.${ver}.cache.$$"
  local package_json cache_root bin_path entry cached_ver

  [[ -d "$HOME/.npm/_npx" ]] || return 1

  while IFS= read -r package_json; do
    cached_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    [[ "$cached_ver" == "$ver" ]] || continue

    bin_path=$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.claude" 2>/dev/null)
    entry="$(dirname "$package_json")/$bin_path"
    [[ -n "$bin_path" && -x "$entry" ]] || continue
    [[ "$("$entry" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" == "$ver" ]] || continue

    cache_root="${package_json%/node_modules/$CVM_NPM_PACKAGE/package.json}"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    cp -R "$cache_root"/. "$temp_dir"/ || {
      rm -rf "$temp_dir"
      continue
    }

    rm -rf "$install_dir"
    mv "$temp_dir" "$install_dir"
    if _cvm_version_installed "$ver"; then
      _cvm_log "已从 npm/npx 缓存导入 Claude Code ${GREEN}v${ver}${NC}"
      return 0
    fi

    rm -rf "$install_dir"
  done < <(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  return 1
}

_cvm_import_global_npm() {
  local ver="$1"
  local install_dir="$CVM_VERSIONS_DIR/$ver"
  local temp_dir="$CVM_VERSIONS_DIR/.${ver}.global.$$"
  local global_root package_dir package_json platform_package

  global_root=$(npm root -g 2>/dev/null) || return 1
  package_dir="$global_root/$CVM_NPM_PACKAGE"
  package_json="$package_dir/package.json"
  [[ -f "$package_json" ]] || return 1
  [[ "$(node -p "require('$package_json').version" 2>/dev/null)" == "$ver" ]] || return 1

  rm -rf "$temp_dir"
  mkdir -p "$temp_dir/node_modules/@anthropic-ai"
  cp -R "$package_dir" "$temp_dir/node_modules/@anthropic-ai/claude-code" || {
    rm -rf "$temp_dir"
    return 1
  }

  platform_package=$(_cvm_platform_package 2>/dev/null)
  if [[ -n "$platform_package" && -d "$global_root/$platform_package" ]]; then
    cp -R "$global_root/$platform_package" "$temp_dir/node_modules/@anthropic-ai/" || {
      rm -rf "$temp_dir"
      return 1
    }
  fi

  rm -rf "$install_dir"
  mv "$temp_dir" "$install_dir"
  if _cvm_version_installed "$ver"; then
    _cvm_log "已从全局 npm 安装导入 Claude Code ${GREEN}v${ver}${NC}"
    return 0
  fi

  rm -rf "$install_dir"
  return 1
}

_cvm_platform_package() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    CYGWIN*|MINGW*|MSYS*) os="win32" ;;
    *) return 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *) return 1 ;;
  esac
  echo "${CVM_NPM_PACKAGE}-${os}-${arch}"
}

_cvm_download_package() {
  local label="$1"
  local package_spec="$2"
  local output_file="$3"
  local metadata tarball integrity expected actual

  metadata=$(npm view "$package_spec" dist.tarball dist.integrity --json --registry="$CVM_REGISTRY" 2>/dev/null) || return 1
  tarball=$(printf '%s' "$metadata" | node -e '
let d=""; process.stdin.on("data", c => d += c); process.stdin.on("end", () => {
  const m=JSON.parse(d); console.log(m["dist.tarball"]);
});')
  integrity=$(printf '%s' "$metadata" | node -e '
let d=""; process.stdin.on("data", c => d += c); process.stdin.on("end", () => {
  const m=JSON.parse(d); console.log(m["dist.integrity"]);
});')

  _cvm_info "${label}（按实际下载字节计算）"
  curl --fail --location --progress-bar --output "$output_file" "$tarball" || return 1

  expected="${integrity#sha512-}"
  actual=$(openssl dgst -sha512 -binary "$output_file" | openssl base64 -A)
  if [[ "$actual" != "$expected" ]]; then
    _cvm_err "${label}完整性校验失败"
    return 1
  fi
  _cvm_log "${label}下载并校验完成"
}

_cvm_install_version() {
  local ver="$1"
  local install_dir="$CVM_VERSIONS_DIR/$ver"
  local temp_dir="$CVM_VERSIONS_DIR/.${ver}.tmp.$$"
  local package_dir="$temp_dir/packages"
  local main_tgz="$package_dir/claude-code.tgz"
  local platform_tgz="$package_dir/claude-code-platform.tgz"
  local platform_package

  _cvm_check_npm || return 1
  _cvm_ensure_dir

  if _cvm_version_installed "$ver"; then
    _cvm_log "Claude Code ${GREEN}v${ver}${NC} 已安装"
    return 0
  fi

  if _cvm_import_npx_cache "$ver"; then
    return 0
  fi

  if _cvm_import_global_npm "$ver"; then
    return 0
  fi

  _cvm_info "未安装 Claude Code ${GREEN}v${ver}${NC}，正在安装 ..."
  if ! _cvm_version_exists "$ver"; then
    _cvm_err "版本 ${ver} 不存在。使用 ${CYAN}cvm remote${NC} 查看可用版本"
    return 1
  fi

  platform_package=$(_cvm_platform_package) || {
    _cvm_err "当前操作系统或 CPU 架构不受支持"
    return 1
  }

  mkdir -p "$package_dir"
  trap 'rm -rf "$temp_dir"; printf "\n"; return 130' INT TERM

  _cvm_download_package "下载主程序包" "${CVM_NPM_PACKAGE}@${ver}" "$main_tgz" || {
    rm -rf "$temp_dir"
    trap - INT TERM
    return 1
  }
  local install_packages=("$main_tgz")
  if _cvm_package_exists "${platform_package}@${ver}"; then
    _cvm_download_package "下载平台包" "${platform_package}@${ver}" "$platform_tgz" || {
      rm -rf "$temp_dir"
      trap - INT TERM
      return 1
    }
    install_packages+=("$platform_tgz")
  else
    _cvm_info "该历史版本使用单包结构，无需下载平台包"
  fi

  _cvm_info "正在解包并安装 ..."
  if npm install \
    --prefix "$temp_dir" \
    --no-audit \
    --no-fund \
    --omit=dev \
    --loglevel=error \
    --progress=false \
    "${install_packages[@]}"; then
    rm -rf "$package_dir"
    rm -rf "$install_dir"
    mv "$temp_dir" "$install_dir"
    trap - INT TERM
    _cvm_log "已安装 Claude Code ${GREEN}v${ver}${NC}"
  else
    _cvm_err "Claude Code v${ver} 安装失败"
    rm -rf "$temp_dir"
    trap - INT TERM
    return 1
  fi
}

# ── Codex helpers ────────────────────────────────────────────────────────────

_cvm_codex_version_from_entry() {
  "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

_cvm_codex_entry() {
  local version_dir="$CVM_CODEX_VERSIONS_DIR/$1"
  local package_dir="$version_dir/node_modules/$CVM_CODEX_NPM_PACKAGE"
  local package_json="$package_dir/package.json"
  local bin_path

  if [[ -x "$version_dir/codex" ]]; then
    echo "$version_dir/codex"
    return 0
  fi

  bin_path=$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.codex" 2>/dev/null)
  [[ -n "$bin_path" ]] && echo "$package_dir/$bin_path"
}

_cvm_codex_version_installed() {
  local ver="$1"
  local entry
  entry=$(_cvm_codex_entry "$ver")
  [[ -n "$entry" && -x "$entry" ]] &&
    [[ "$(_cvm_codex_version_from_entry "$entry")" == "$ver" ]]
}

_cvm_codex_import_package_root() {
  local ver="$1"
  local source_root="$2"
  local source_label="$3"
  local install_dir="$CVM_CODEX_VERSIONS_DIR/$ver"
  local temp_dir="$CVM_CODEX_VERSIONS_DIR/.${ver}.import.$$"

  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"
  cp -R "$source_root"/. "$temp_dir"/ || {
    rm -rf "$temp_dir"
    return 1
  }

  rm -rf "$install_dir"
  mv "$temp_dir" "$install_dir"
  if _cvm_codex_version_installed "$ver"; then
    _cvm_log "已从${source_label}导入 Codex ${GREEN}v${ver}${NC}"
    return 0
  fi

  rm -rf "$install_dir"
  return 1
}

_cvm_codex_import_npx_cache() {
  local ver="$1"
  local package_json cached_ver cache_root

  while IFS= read -r package_json; do
    cached_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    [[ "$cached_ver" == "$ver" ]] || continue
    cache_root="${package_json%/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json}"
    _cvm_codex_import_package_root "$ver" "$cache_root" " npx 缓存" && return 0
  done < <(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  return 1
}

_cvm_codex_import_global_npm() {
  local ver="$1"
  local package_json cached_ver global_root

  while IFS= read -r package_json; do
    cached_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    [[ "$cached_ver" == "$ver" ]] || continue
    global_root="${package_json%/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json}"
    _cvm_codex_import_package_root "$ver" "$global_root" "全局 npm " && return 0
  done < <(find "$HOME/.nvm/versions" -path "*/lib/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  return 1
}

_cvm_codex_import_current_binary() {
  local ver="$1"
  local current_entry current_ver install_dir temp_dir

  current_entry=$(command -v codex 2>/dev/null) || return 1
  current_ver=$(_cvm_codex_version_from_entry "$current_entry")
  [[ "$current_ver" == "$ver" ]] || return 1

  install_dir="$CVM_CODEX_VERSIONS_DIR/$ver"
  temp_dir="$CVM_CODEX_VERSIONS_DIR/.${ver}.binary.$$"
  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"
  cp "$current_entry" "$temp_dir/codex" || {
    rm -rf "$temp_dir"
    return 1
  }
  chmod +x "$temp_dir/codex"
  rm -rf "$install_dir"
  mv "$temp_dir" "$install_dir"

  if _cvm_codex_version_installed "$ver"; then
    _cvm_log "已从当前系统安装导入 Codex ${GREEN}v${ver}${NC}"
    return 0
  fi

  rm -rf "$install_dir"
  return 1
}

_cvm_codex_install_version() {
  local ver="$1"
  local install_dir="$CVM_CODEX_VERSIONS_DIR/$ver"
  local temp_dir="$CVM_CODEX_VERSIONS_DIR/.${ver}.tmp.$$"

  _cvm_check_npm || return 1
  _cvm_ensure_dir

  if _cvm_codex_version_installed "$ver"; then
    _cvm_log "Codex ${GREEN}v${ver}${NC} 已安装"
    return 0
  fi
  _cvm_codex_import_npx_cache "$ver" && return 0
  _cvm_codex_import_global_npm "$ver" && return 0
  _cvm_codex_import_current_binary "$ver" && return 0

  _cvm_info "未安装 Codex ${GREEN}v${ver}${NC}，正在安装 ..."
  if [[ "$(npm view "${CVM_CODEX_NPM_PACKAGE}@${ver}" version --registry="$CVM_REGISTRY" 2>/dev/null)" != "$ver" ]]; then
    _cvm_err "Codex 版本 ${ver} 不存在或 npm 暂时不可用"
    return 1
  fi

  rm -rf "$temp_dir"
  if npm install \
    --prefix "$temp_dir" \
    --no-audit \
    --no-fund \
    --omit=dev \
    --loglevel=error \
    --progress=false \
    "${CVM_CODEX_NPM_PACKAGE}@${ver}"; then
    rm -rf "$install_dir"
    mv "$temp_dir" "$install_dir"
    if _cvm_codex_version_installed "$ver"; then
      _cvm_log "已安装 Codex ${GREEN}v${ver}${NC}"
      return 0
    fi
  fi

  rm -rf "$temp_dir" "$install_dir"
  _cvm_err "Codex v${ver} 安装失败"
  return 1
}

_cvm_codex_use() {
  local ver="$1"
  shift
  [[ -n "$ver" ]] || {
    _cvm_err "请指定 Codex 版本。例如: ${CYAN}codex-v 0.139.0${NC}"
    return 1
  }
  _cvm_codex_install_version "$ver" || return 1
  _cvm_info "启动 Codex ${GREEN}v${ver}${NC} ..."
  "$(_cvm_codex_entry "$ver")" "$@"
}

_cvm_codex_installed() {
  _cvm_ensure_dir
  local records dir ver package_json entry current_entry current_ver
  records=$(mktemp)

  while IFS= read -r dir; do
    ver=$(basename "$dir")
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    _cvm_codex_version_installed "$ver" && printf '%s|CVM\n' "$ver" >> "$records"
  done < <(find "$CVM_CODEX_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

  while IFS= read -r package_json; do
    ver=$(node -p "require('$package_json').version" 2>/dev/null)
    entry="$(dirname "$package_json")/$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.codex" 2>/dev/null)"
    [[ -x "$entry" && "$(_cvm_codex_version_from_entry "$entry")" == "$ver" ]] &&
      printf '%s|npx 缓存\n' "$ver" >> "$records"
  done < <(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  while IFS= read -r package_json; do
    ver=$(node -p "require('$package_json').version" 2>/dev/null)
    entry="$(dirname "$package_json")/$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.codex" 2>/dev/null)"
    [[ -x "$entry" && "$(_cvm_codex_version_from_entry "$entry")" == "$ver" ]] &&
      printf '%s|全局 npm\n' "$ver" >> "$records"
  done < <(find "$HOME/.nvm/versions" -path "*/lib/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  current_entry=$(command -v codex 2>/dev/null)
  if [[ -n "$current_entry" ]]; then
    current_ver=$(_cvm_codex_version_from_entry "$current_entry")
    [[ -n "$current_ver" ]] && printf '%s|系统安装\n' "$current_ver" >> "$records"
  fi

  echo -e "\n${BOLD}Codex 本地可用版本:${NC}"
  echo -e "───────────────────────────────────────────"
  if [[ ! -s "$records" ]]; then
    echo -e "  ${DIM}(暂无本地可用版本)${NC}"
  else
    sort -t'|' -k1,1V -k2,2 -u "$records" | awk -F'|' '
      function flush() {
        if (version != "") printf "  \033[0;32m✔\033[0m %-12s \033[2m%s\033[0m\n", version, sources
      }
      {
        if ($1 != version) {
          flush()
          version = $1
          sources = $2
        } else {
          sources = sources " / " $2
        }
      }
      END { flush() }
    '
  fi
  rm -f "$records"
  echo -e "───────────────────────────────────────────\n"
}

_cvm_codex_uninstall() {
  local ver="$1"
  local removed=false dir package_json cached_ver

  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    _cvm_err "请指定有效 Codex 版本。例如: ${CYAN}codex-v-r 0.139.0${NC}"
    return 1
  }

  if [[ -d "$CVM_CODEX_VERSIONS_DIR/$ver" ]]; then
    rm -rf "$CVM_CODEX_VERSIONS_DIR/$ver"
    _cvm_log "已删除 CVM Codex 安装 ${GREEN}v${ver}${NC}"
    removed=true
  fi

  while IFS= read -r dir; do
    rm -rf "$dir"
    removed=true
  done < <(find "$CVM_CODEX_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name ".${ver}.*" 2>/dev/null)

  while IFS= read -r package_json; do
    cached_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    [[ "$cached_ver" == "$ver" ]] || continue
    dir="${package_json%/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json}"
    rm -rf "$dir"
    _cvm_log "已删除 Codex npx 缓存 ${GREEN}v${ver}${NC}"
    removed=true
  done < <(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  if $removed; then
    _cvm_log "Codex ${GREEN}v${ver}${NC} 已从 CVM 和 npx 缓存卸载"
  else
    _cvm_warn "未找到 Codex v${ver} 的 CVM 安装或 npx 缓存"
  fi
}

_cvm_codex_releases() {
  npm view "$CVM_CODEX_NPM_PACKAGE" time --json --registry="$CVM_REGISTRY" 2>/dev/null | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const times = JSON.parse(input);
  Object.entries(times)
    .filter(([version]) => /^\d+\.\d+\.\d+$/.test(version))
    .sort((a, b) => new Date(b[1]) - new Date(a[1]))
    .forEach(([version, time]) => console.log(`${version.padEnd(16)} ${new Date(time).toLocaleString()}`));
});
'
}

_cvm_codex_command() {
  local cmd="${1:-}"
  shift 2>/dev/null
  case "$cmd" in
    use) _cvm_codex_use "$@" ;;
    install) _cvm_codex_install_version "$1" ;;
    uninstall|remove|rm) _cvm_codex_uninstall "$1" ;;
    installed|list|ls) _cvm_codex_installed ;;
    current) codex --version ;;
    remote) npm view "$CVM_CODEX_NPM_PACKAGE" versions --json --registry="$CVM_REGISTRY" ;;
    releases) _cvm_codex_releases ;;
    *)
      _cvm_err "用法: cvm codex use|install|uninstall|installed|current|remote|releases [版本]"
      return 1
      ;;
  esac
}

# ── Detection and config inspection ─────────────────────────────────────────

_cvm_file_report() {
  local label="$1"
  local file="$2"

  if [[ -f "$file" ]]; then
    node - "$label" "$file" <<'JS'
const fs = require("fs");
const [label, file] = process.argv.slice(2);
const stat = fs.statSync(file);
const modified = new Intl.DateTimeFormat("zh-CN", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hour12: false,
}).format(stat.mtime).replace(/\//g, "-");
console.log(`  \x1b[0;32m✔\x1b[0m ${label}: ${file}`);
console.log(`      大小: ${stat.size} bytes  修改: ${modified}`);
JS
  else
    echo -e "  ${DIM}·${NC} ${label}: ${file} ${DIM}(不存在)${NC}"
  fi
}

_cvm_json_config_summary() {
  local file="$1"
  local show_secrets="${2:-false}"
  [[ -f "$file" ]] || return 0

  node - "$file" "$show_secrets" <<'JS'
const fs = require("fs");
const file = process.argv[2];
const showSecrets = process.argv[3] === "true";
const important = /(api|base.?url|url|endpoint|host|model|provider|token|secret|password|passwd|auth|oauth|cookie|session|credential|login|account|email|org|organization|permission|bypass|danger|proxy|region|workspace)/i;
const sensitive = /(api.?key|token|secret|password|passwd|auth|cookie|session|credential)/i;
const rows = [];

function describe(value, key) {
  if (value === null) return "null";
  if (Array.isArray(value)) return `array(${value.length})`;
  if (typeof value === "object") return `object(${Object.keys(value).length} keys)`;
  if (!showSecrets && sensitive.test(key)) return `${typeof value}(len=${String(value).length}) <redacted>`;
  if (typeof value === "string") return value.length > 140 ? `${value.slice(0, 137)}...` : value;
  return String(value);
}

function walk(value, path = []) {
  const joined = path.join(".");
  if (/projects|cache|cached|tip|history|changelog|statsig|growthbook|experiments?|firstStartTime|firstTokenDate|numStartups|promptQueue|closedIssues/i.test(joined)) {
    return;
  }
  if (path.length && important.test(joined)) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      rows.push([joined, describe(value, path.at(-1) || "")]);
    }
  }
  if (!value || typeof value !== "object" || path.length >= 6) return;
  for (const [key, child] of Object.entries(value)) walk(child, path.concat(key));
}

try {
  walk(JSON.parse(fs.readFileSync(file, "utf8")));
  if (rows.length) {
    console.log("      关键配置:");
    for (const [path, value] of rows.slice(0, 120)) {
      console.log(`        ${path}: ${value}`);
    }
    if (rows.length > 120) console.log(`        ... 另有 ${rows.length - 120} 项`);
  } else {
    console.log("      关键配置: 未发现");
  }
} catch (error) {
  console.log(`      关键配置解析失败: ${error.message}`);
}
JS
}

_cvm_text_config_summary() {
  local file="$1"
  local show_secrets="${2:-false}"
  [[ -f "$file" ]] || return 0

  node - "$file" "$show_secrets" <<'JS'
const fs = require("fs");
const file = process.argv[2];
const showSecrets = process.argv[3] === "true";
const important = /(api|base.?url|url|endpoint|host|model|provider|token|secret|password|passwd|auth|oauth|cookie|session|credential|login|account|email|org|organization|permission|bypass|danger|proxy|region|workspace)/i;
const sensitive = /(api.?key|token|secret|password|passwd|auth|cookie|session|credential)/i;
const lines = fs.readFileSync(file, "utf8")
  .split(/\r?\n/)
  .map(line => line.trimEnd())
  .filter(line => line.trim() && !line.trim().startsWith("#") && important.test(line))
  .slice(0, 120)
  .map(line => {
    const key = line.split("=")[0] || "";
    if (!showSecrets && sensitive.test(key)) return line.replace(/=.*/, "= <redacted>");
    return line.length > 160 ? `${line.slice(0, 157)}...` : line;
  });

if (lines.length) {
  console.log("      关键配置:");
  console.log(lines.map(line => `      ${line}`).join("\n"));
} else {
  console.log("      关键配置: 未发现");
}
JS
}

_cvm_detect_claude() {
  local current_entry current_ver global_root package_json global_ver count

  echo -e "\n${BOLD}Claude Code 安装检测:${NC}"
  echo -e "───────────────────────────────────────────"

  current_entry=$(command -v claude 2>/dev/null)
  if [[ -n "$current_entry" ]]; then
    current_ver=$(_cvm_current_version)
    echo -e "  ${GREEN}✔${NC} PATH    ${current_entry} ${DIM}${current_ver:+v$current_ver}${NC}"
  else
    echo -e "  ${DIM}·${NC} PATH    未找到 claude"
  fi

  count=$(find "$CVM_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}✔${NC} CVM     ${CVM_VERSIONS_DIR} ${DIM}(${count:-0} 个目录)${NC}"

  global_root=$(npm root -g 2>/dev/null)
  package_json="$global_root/$CVM_NPM_PACKAGE/package.json"
  if [[ -f "$package_json" ]]; then
    global_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    echo -e "  ${GREEN}✔${NC} npm -g  ${global_root}/$CVM_NPM_PACKAGE ${DIM}${global_ver:+v$global_ver}${NC}"
  else
    echo -e "  ${DIM}·${NC} npm -g  未找到 ${CVM_NPM_PACKAGE}"
  fi

  count=$(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_NPM_PACKAGE/package.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}✔${NC} npx     ${HOME}/.npm/_npx ${DIM}(${count:-0} 个缓存)${NC}"
  echo -e "───────────────────────────────────────────\n"
}

_cvm_detect_codex() {
  local current_entry current_ver global_root package_json global_ver count

  echo -e "\n${BOLD}Codex 安装检测:${NC}"
  echo -e "───────────────────────────────────────────"

  current_entry=$(command -v codex 2>/dev/null)
  if [[ -n "$current_entry" ]]; then
    current_ver=$(_cvm_codex_version_from_entry "$current_entry")
    echo -e "  ${GREEN}✔${NC} PATH    ${current_entry} ${DIM}${current_ver:+v$current_ver}${NC}"
  else
    echo -e "  ${DIM}·${NC} PATH    未找到 codex"
  fi

  count=$(find "$CVM_CODEX_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}✔${NC} CVM     ${CVM_CODEX_VERSIONS_DIR} ${DIM}(${count:-0} 个目录)${NC}"

  global_root=$(npm root -g 2>/dev/null)
  package_json="$global_root/$CVM_CODEX_NPM_PACKAGE/package.json"
  if [[ -f "$package_json" ]]; then
    global_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    echo -e "  ${GREEN}✔${NC} npm -g  ${global_root}/$CVM_CODEX_NPM_PACKAGE ${DIM}${global_ver:+v$global_ver}${NC}"
  else
    echo -e "  ${DIM}·${NC} npm -g  未找到 ${CVM_CODEX_NPM_PACKAGE}"
  fi

  count=$(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_CODEX_NPM_PACKAGE/package.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}✔${NC} npx     ${HOME}/.npm/_npx ${DIM}(${count:-0} 个缓存)${NC}"
  echo -e "───────────────────────────────────────────\n"
}

_cvm_var_value() {
  local name="$1"
  local value
  eval "value=\"\${${name}:-}\""
  printf '%s' "$value"
}

_cvm_print_config_value() {
  local label="$1"
  local value="$2"
  local show_raw="${3:-true}"
  local default_text="${4:-未配置}"
  local sensitive="${5:-false}"

  if [[ -z "$value" ]]; then
    echo -e "    ${label}: ${DIM}${default_text}${NC}"
  elif [[ "$sensitive" == "true" && "$show_raw" != "true" ]]; then
    echo "    ${label}: $(printf '%s' "$value" | node -e 'let d=""; process.stdin.on("data", c => d += c); process.stdin.on("end", () => console.log(`${typeof d}(len=${d.length}) <redacted>`));')"
  else
    echo "    ${label}: ${value}"
  fi
}

_cvm_core_config_claude() {
  local show_secrets="$1"
  local model api_url api_key auth_token provider proxy

  model=$(_cvm_var_value ANTHROPIC_MODEL)
  api_url=$(_cvm_var_value ANTHROPIC_BASE_URL)
  api_key=$(_cvm_var_value ANTHROPIC_API_KEY)
  auth_token=$(_cvm_var_value ANTHROPIC_AUTH_TOKEN)
  provider="official"
  if [[ "$(_cvm_var_value CLAUDE_CODE_USE_BEDROCK)" == "1" || "$(_cvm_var_value CLAUDE_CODE_USE_BEDROCK)" == "true" ]]; then
    provider="bedrock"
  elif [[ "$(_cvm_var_value CLAUDE_CODE_USE_VERTEX)" == "1" || "$(_cvm_var_value CLAUDE_CODE_USE_VERTEX)" == "true" ]]; then
    provider="vertex"
  fi
  proxy="$(_cvm_var_value HTTPS_PROXY)"
  [[ -n "$proxy" ]] || proxy="$(_cvm_var_value HTTP_PROXY)"

  echo -e "  ${BOLD}当前核心配置:${NC}"
  _cvm_print_config_value "模型 ANTHROPIC_MODEL" "$model" true "未配置，使用 Claude Code 默认/文件 model"
  _cvm_print_config_value "API URL ANTHROPIC_BASE_URL" "$api_url" true "未配置，使用 Claude 官方默认"
  _cvm_print_config_value "API Key ANTHROPIC_API_KEY" "$api_key" "$show_secrets" "未配置" true
  _cvm_print_config_value "Auth Token ANTHROPIC_AUTH_TOKEN" "$auth_token" "$show_secrets" "未配置" true
  echo "    Provider: ${provider}"
  _cvm_print_config_value "Proxy HTTP(S)_PROXY" "$proxy" "$show_secrets" "未配置" true
}

_cvm_core_config_codex() {
  local show_secrets="$1"
  local model api_url api_key org project proxy

  model=$(_cvm_var_value OPENAI_MODEL)
  api_url=$(_cvm_var_value OPENAI_BASE_URL)
  [[ -n "$api_url" ]] || api_url=$(_cvm_var_value OPENAI_API_BASE)
  api_key=$(_cvm_var_value OPENAI_API_KEY)
  org=$(_cvm_var_value OPENAI_ORG_ID)
  project=$(_cvm_var_value OPENAI_PROJECT_ID)
  proxy="$(_cvm_var_value HTTPS_PROXY)"
  [[ -n "$proxy" ]] || proxy="$(_cvm_var_value HTTP_PROXY)"

  echo -e "  ${BOLD}当前核心配置:${NC}"
  _cvm_print_config_value "模型 OPENAI_MODEL" "$model" true "未配置，使用 Codex 默认/文件 model"
  _cvm_print_config_value "API URL OPENAI_BASE_URL" "$api_url" true "未配置，使用 OpenAI 官方默认"
  _cvm_print_config_value "API Key OPENAI_API_KEY" "$api_key" "$show_secrets" "未配置" true
  _cvm_print_config_value "Org OPENAI_ORG_ID" "$org" true
  _cvm_print_config_value "Project OPENAI_PROJECT_ID" "$project" true
  _cvm_print_config_value "Proxy HTTP(S)_PROXY" "$proxy" "$show_secrets" "未配置" true
}

_cvm_env_write() {
  local action="$1"
  local name="$2"
  local value="${3:-}"

  _cvm_ensure_dir
  node - "$CVM_ENV_FILE" "$action" "$name" "$value" <<'JS'
const fs = require("fs");
const [file, action, name, value] = process.argv.slice(2);
const vars = [
  "ANTHROPIC_BASE_URL",
  "ANTHROPIC_API_KEY",
  "ANTHROPIC_AUTH_TOKEN",
  "ANTHROPIC_MODEL",
  "CLAUDE_CODE_USE_BEDROCK",
  "CLAUDE_CODE_USE_VERTEX",
  "OPENAI_BASE_URL",
  "OPENAI_API_KEY",
  "OPENAI_MODEL",
  "OPENAI_ORG_ID",
  "OPENAI_PROJECT_ID",
  "HTTPS_PROXY",
  "HTTP_PROXY",
];

if (!vars.includes(name)) {
  console.error(`Unsupported config variable: ${name}`);
  process.exit(1);
}

const env = {};
for (const key of vars) {
  if (process.env[key]) env[key] = process.env[key];
}

if (action === "set") {
  env[name] = value;
} else if (action === "clear") {
  delete env[name];
} else {
  console.error(`Unsupported action: ${action}`);
  process.exit(1);
}

function quoteShell(raw) {
  return `'${String(raw).replace(/'/g, `'\\''`)}'`;
}

const lines = [
  "# Generated by CVM. Edit with `cvm config set` or `cvm menu`.",
  "",
];
for (const key of vars) {
  if (env[key]) lines.push(`export ${key}=${quoteShell(env[key])}`);
}
fs.writeFileSync(file, `${lines.join("\n")}\n`);
JS
}

_cvm_config_var() {
  local target="$1"
  local field="$2"

  case "$target:$field" in
    claude:api-url|claude:url|claude:base-url) echo "ANTHROPIC_BASE_URL" ;;
    claude:api-key|claude:key) echo "ANTHROPIC_API_KEY" ;;
    claude:auth-token|claude:token) echo "ANTHROPIC_AUTH_TOKEN" ;;
    claude:model) echo "ANTHROPIC_MODEL" ;;
    codex:api-url|codex:url|codex:base-url) echo "OPENAI_BASE_URL" ;;
    codex:api-key|codex:key) echo "OPENAI_API_KEY" ;;
    codex:model) echo "OPENAI_MODEL" ;;
    codex:org|codex:organization) echo "OPENAI_ORG_ID" ;;
    codex:project) echo "OPENAI_PROJECT_ID" ;;
    all:proxy|claude:proxy|codex:proxy) echo "HTTPS_PROXY" ;;
    *)
      return 1
      ;;
  esac
}

_cvm_config_set_var() {
  local var_name="$1"
  local value="$2"

  _cvm_env_write set "$var_name" "$value" || return 1
  export "$var_name=$value"
  _cvm_log "已设置 ${CYAN}${var_name}${NC}"
}

_cvm_config_clear_var() {
  local var_name="$1"

  _cvm_env_write clear "$var_name" || return 1
  unset "$var_name"
  _cvm_log "已清除 ${CYAN}${var_name}${NC}"
}

_cvm_config_set_provider() {
  local provider="$1"

  case "$provider" in
    official)
      _cvm_config_clear_var CLAUDE_CODE_USE_BEDROCK >/dev/null
      _cvm_config_clear_var CLAUDE_CODE_USE_VERTEX >/dev/null
      _cvm_log "Claude provider 已设置为 ${CYAN}official${NC}"
      ;;
    bedrock)
      _cvm_config_set_var CLAUDE_CODE_USE_BEDROCK 1 >/dev/null
      _cvm_config_clear_var CLAUDE_CODE_USE_VERTEX >/dev/null
      _cvm_log "Claude provider 已设置为 ${CYAN}bedrock${NC}"
      ;;
    vertex)
      _cvm_config_set_var CLAUDE_CODE_USE_VERTEX 1 >/dev/null
      _cvm_config_clear_var CLAUDE_CODE_USE_BEDROCK >/dev/null
      _cvm_log "Claude provider 已设置为 ${CYAN}vertex${NC}"
      ;;
    *)
      _cvm_err "provider 只能是 official、bedrock 或 vertex"
      return 1
      ;;
  esac
}

_cvm_config_set() {
  local target="${1:-}"
  local field="${2:-}"
  local value="${3:-}"
  local var_name

  if [[ "$target" == "claude" && "$field" == "provider" ]]; then
    _cvm_config_set_provider "$value"
    return $?
  fi

  if [[ -z "$target" || -z "$field" || -z "$value" ]]; then
    _cvm_err "用法: cvm config set claude|codex <api-url|api-key|model|...> <值>"
    return 1
  fi

  var_name=$(_cvm_config_var "$target" "$field") || {
    _cvm_err "不支持的配置项: ${target} ${field}"
    return 1
  }
  _cvm_config_set_var "$var_name" "$value"
}

_cvm_config_clear() {
  local target="${1:-}"
  local field="${2:-}"
  local var_name

  if [[ "$target" == "claude" && "$field" == "provider" ]]; then
    _cvm_config_set_provider official
    return $?
  fi

  if [[ -z "$target" || -z "$field" ]]; then
    _cvm_err "用法: cvm config clear claude|codex <api-url|api-key|model|...>"
    return 1
  fi

  var_name=$(_cvm_config_var "$target" "$field") || {
    _cvm_err "不支持的配置项: ${target} ${field}"
    return 1
  }
  _cvm_config_clear_var "$var_name"
}

_cvm_prompt_value() {
  local label="$1"
  local current="$2"
  local value

  if [[ -n "$current" ]]; then
    printf '%b' "${label} ${DIM}(当前: ${current})${NC}: "
  else
    printf '%b' "${label}: "
  fi
  IFS= read -r value
  if [[ -z "$value" ]]; then
    value="$current"
  fi
  printf '%s' "$value"
}

_cvm_menu_claude() {
  local choice value
  while true; do
    echo -e "\n${BOLD}Claude 配置菜单${NC}"
    echo "  1) 设置 API URL"
    echo "  2) 设置 API Key"
    echo "  3) 设置 Auth Token"
    echo "  4) 设置模型"
    echo "  5) 设置 Provider (official/bedrock/vertex)"
    echo "  6) 清除 API URL"
    echo "  7) 清除 API Key"
    echo "  8) 查看配置"
    echo "  0) 返回"
    printf '请选择: '
    IFS= read -r choice
    case "$choice" in
      1) value=$(_cvm_prompt_value "API URL" "${ANTHROPIC_BASE_URL:-}"); [[ -n "$value" ]] && _cvm_config_set claude api-url "$value" ;;
      2) value=$(_cvm_prompt_value "API Key" "${ANTHROPIC_API_KEY:-}"); [[ -n "$value" ]] && _cvm_config_set claude api-key "$value" ;;
      3) value=$(_cvm_prompt_value "Auth Token" "${ANTHROPIC_AUTH_TOKEN:-}"); [[ -n "$value" ]] && _cvm_config_set claude auth-token "$value" ;;
      4) value=$(_cvm_prompt_value "模型" "${ANTHROPIC_MODEL:-}"); [[ -n "$value" ]] && _cvm_config_set claude model "$value" ;;
      5) value=$(_cvm_prompt_value "Provider" "official"); [[ -n "$value" ]] && _cvm_config_set claude provider "$value" ;;
      6) _cvm_config_clear claude api-url ;;
      7) _cvm_config_clear claude api-key ;;
      8) _cvm_config_claude false ;;
      0) return 0 ;;
      *) _cvm_warn "无效选项" ;;
    esac
  done
}

_cvm_menu_codex() {
  local choice value
  while true; do
    echo -e "\n${BOLD}Codex 配置菜单${NC}"
    echo "  1) 设置 API URL"
    echo "  2) 设置 API Key"
    echo "  3) 设置模型"
    echo "  4) 设置 Org"
    echo "  5) 设置 Project"
    echo "  6) 清除 API URL"
    echo "  7) 清除 API Key"
    echo "  8) 查看配置"
    echo "  0) 返回"
    printf '请选择: '
    IFS= read -r choice
    case "$choice" in
      1) value=$(_cvm_prompt_value "API URL" "${OPENAI_BASE_URL:-}"); [[ -n "$value" ]] && _cvm_config_set codex api-url "$value" ;;
      2) value=$(_cvm_prompt_value "API Key" "${OPENAI_API_KEY:-}"); [[ -n "$value" ]] && _cvm_config_set codex api-key "$value" ;;
      3) value=$(_cvm_prompt_value "模型" "${OPENAI_MODEL:-}"); [[ -n "$value" ]] && _cvm_config_set codex model "$value" ;;
      4) value=$(_cvm_prompt_value "Org" "${OPENAI_ORG_ID:-}"); [[ -n "$value" ]] && _cvm_config_set codex org "$value" ;;
      5) value=$(_cvm_prompt_value "Project" "${OPENAI_PROJECT_ID:-}"); [[ -n "$value" ]] && _cvm_config_set codex project "$value" ;;
      6) _cvm_config_clear codex api-url ;;
      7) _cvm_config_clear codex api-key ;;
      8) _cvm_config_codex false ;;
      0) return 0 ;;
      *) _cvm_warn "无效选项" ;;
    esac
  done
}

cvm_menu() {
  local choice
  while true; do
    echo -e "\n${BOLD}CVM 交互式菜单${NC}"
    echo "  1) Claude 配置"
    echo "  2) Codex 配置"
    echo "  3) 查看全部配置"
    echo "  4) 环境检测"
    echo "  0) 退出"
    printf '请选择: '
    IFS= read -r choice
    case "$choice" in
      1) _cvm_menu_claude ;;
      2) _cvm_menu_codex ;;
      3) cvm_config all ;;
      4) cvm_detect all ;;
      0) return 0 ;;
      *) _cvm_warn "无效选项" ;;
    esac
  done
}

cvm_detect() {
  local target="${1:-all}"
  case "$target" in
    all) _cvm_detect_claude; _cvm_detect_codex ;;
    claude) _cvm_detect_claude ;;
    codex) _cvm_detect_codex ;;
    *)
      _cvm_err "用法: cvm detect [claude|codex]"
      return 1
      ;;
  esac
}

_cvm_config_claude() {
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local show_secrets="${1:-false}"

  echo -e "\n${BOLD}Claude Code 配置:${NC}"
  echo -e "───────────────────────────────────────────"
  if [[ "$show_secrets" == "true" ]]; then
    echo -e "  ${YELLOW}敏感值显示: 已开启${NC}"
  fi
  _cvm_core_config_claude "$show_secrets"
  echo -e "  目录: ${config_dir}"
  _cvm_file_report "settings.json" "$config_dir/settings.json"
  _cvm_json_config_summary "$config_dir/settings.json" "$show_secrets"
  _cvm_file_report "settings.local.json" "$config_dir/settings.local.json"
  _cvm_json_config_summary "$config_dir/settings.local.json" "$show_secrets"
  _cvm_file_report ".claude.json" "$HOME/.claude.json"
  _cvm_json_config_summary "$HOME/.claude.json" "$show_secrets"
  echo -e "───────────────────────────────────────────\n"
}

_cvm_config_codex() {
  local config_dir="${CODEX_HOME:-$HOME/.codex}"
  local show_secrets="${1:-false}"

  echo -e "\n${BOLD}Codex 配置:${NC}"
  echo -e "───────────────────────────────────────────"
  if [[ "$show_secrets" == "true" ]]; then
    echo -e "  ${YELLOW}敏感值显示: 已开启${NC}"
  fi
  _cvm_core_config_codex "$show_secrets"
  echo -e "  目录: ${config_dir}"
  _cvm_file_report "config.toml" "$config_dir/config.toml"
  _cvm_text_config_summary "$config_dir/config.toml" "$show_secrets"
  _cvm_file_report "auth.json" "$config_dir/auth.json"
  _cvm_json_config_summary "$config_dir/auth.json" "$show_secrets"
  _cvm_file_report "AGENTS.md" "$config_dir/AGENTS.md"
  echo -e "───────────────────────────────────────────\n"
}

cvm_config() {
  local target="all"
  local show_secrets=false

  case "${1:-}" in
    set)
      shift
      _cvm_config_set "$@"
      return $?
      ;;
    clear|unset)
      shift
      _cvm_config_clear "$@"
      return $?
      ;;
    edit|menu)
      cvm_menu
      return $?
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      all|claude|codex) target="$1" ;;
      --show-secrets|--raw) show_secrets=true ;;
      *)
        _cvm_err "用法: cvm config [claude|codex] [--show-secrets]"
        return 1
        ;;
    esac
    shift
  done

  case "$target" in
    all) _cvm_config_claude "$show_secrets"; _cvm_config_codex "$show_secrets" ;;
    claude) _cvm_config_claude "$show_secrets" ;;
    codex) _cvm_config_codex "$show_secrets" ;;
    *)
      _cvm_err "用法: cvm config [claude|codex] [--show-secrets]"
      return 1
      ;;
  esac
}

# ── Commands ─────────────────────────────────────────────────────────────────

# Show help
cvm_help() {
  printf '%b\n' "
${BOLD}CVM${NC} ${DIM}v${CVM_VERSION}${NC} - Claude Code / Codex Version Manager

${BOLD}用法${NC}
  cvm <command> [arguments]

${BOLD}版本安装与运行${NC}
  ${CYAN}cvm use <版本>${NC}
      运行指定版本；本地没有时自动下载安装
  ${CYAN}cvm install <版本>${NC}
      只安装指定版本，不启动 Claude Code
  ${CYAN}cvm uninstall <版本>${NC}
      卸载指定版本的 CVM、npx 缓存和全局 npm 安装
  ${CYAN}cvm default <版本>${NC}
      把指定版本安装为系统全局默认 claude
  ${CYAN}cvm pin <版本> [别名]${NC}
      收藏常用版本，可附加 stable 等别名
  ${CYAN}cvm unpin <版本|别名>${NC}
      从收藏列表移除，不会卸载本地版本

${BOLD}版本查询${NC}
  ${CYAN}cvm installed${NC}               列出本地完整安装的版本
  ${CYAN}cvm list | cvm ls${NC}            列出收藏的版本和别名
  ${CYAN}cvm current${NC}                 显示当前系统全局 claude 版本
  ${CYAN}cvm remote [--all]${NC}          显示最近 20 个或全部可安装版本
  ${CYAN}cvm releases${NC}                显示全部版本及具体发布时间
  ${CYAN}cvm changelog [版本]${NC}        打开指定版本的 GitHub 更新日志

${BOLD}维护与诊断${NC}
  ${CYAN}cvm self-update${NC}             更新 CVM 管理脚本
  ${CYAN}cvm update${NC}                  将系统全局 claude 更新到最新版
  ${CYAN}cvm clean${NC}                   清理 npm/npx 下载缓存
  ${CYAN}cvm doctor${NC}                  检查 Node.js、npm、CVM 和 Claude 环境
  ${CYAN}cvm detect [claude|codex]${NC}   检测 Claude/Codex 安装来源
  ${CYAN}cvm config [claude|codex]${NC}   读取配置文件信息，默认脱敏
  ${CYAN}cvm config ... --show-secrets${NC} 显示认证/API 原始值
  ${CYAN}cvm config set <目标> <项> <值>${NC} 设置 API URL、Key、模型等
  ${CYAN}cvm config clear <目标> <项>${NC} 清除 CVM 管理的配置项
  ${CYAN}cvm menu | cvm config edit${NC}  打开交互式配置菜单
  ${CYAN}cvm version | cvm -v${NC}        显示 CVM 自身版本
  ${CYAN}cvm help | cvm -h${NC}           显示本指令说明

${BOLD}Codex 管理${NC}
  ${CYAN}cvm codex use <版本>${NC}        安装并运行指定 Codex 版本
  ${CYAN}cvm codex install <版本>${NC}    安装指定 Codex 版本
  ${CYAN}cvm codex uninstall <版本>${NC}  卸载指定 Codex 版本
  ${CYAN}cvm codex installed${NC}         列出 Codex 本地可用版本
  ${CYAN}cvm codex current${NC}           显示当前系统 Codex 版本
  ${CYAN}cvm codex remote${NC}            列出 npm 可用 Codex 版本
  ${CYAN}cvm codex releases${NC}          列出 Codex 版本发布时间

${BOLD}快捷指令${NC}
  ${CYAN}claude-<版本>${NC}               自动安装并运行，例如 claude-2.1.175
  ${CYAN}claude-auto-<版本>${NC}          指定版本免权限确认运行
  ${CYAN}claude-v <版本>${NC}             等同 cvm use <版本>
  ${CYAN}claude-l-a | claude-v-a${NC}     列出本地可用版本
  ${CYAN}claude-v-l${NC}                  列出全部版本及发布时间
  ${CYAN}claude-v-r <版本>${NC}           卸载指定版本
  ${CYAN}claude-auto${NC}                 当前全局版本免权限确认运行
  ${CYAN}claude-install <版本>${NC}       安装指定 Claude Code 版本
  ${CYAN}claude-current${NC}              显示当前系统 Claude Code 版本
  ${CYAN}claude-uninstall <版本>${NC}     卸载指定 Claude Code 版本
  ${CYAN}claude-remove <版本>${NC}        等同 claude-uninstall
  ${CYAN}claude-latest${NC}               临时运行 npm 最新版本
  ${CYAN}claude-versions${NC}             查看 npm 全部可用版本
  ${CYAN}claude-clean${NC}                清理 npm/npx 缓存
  ${CYAN}claude-update${NC}               更新系统全局 Claude Code
  ${CYAN}claude-detect${NC}               检测 Claude Code 安装来源
  ${CYAN}claude-config${NC}               读取 Claude Code 配置文件信息
  ${CYAN}codex-<版本>${NC}                自动安装并运行指定 Codex 版本
  ${CYAN}codex-auto-<版本>${NC}           指定版本跳过审批与沙箱运行
  ${CYAN}codex-v <版本>${NC}              等同 cvm codex use <版本>
  ${CYAN}codex-l-a | codex-v-a${NC}       列出 Codex 本地可用版本
  ${CYAN}codex-v-l${NC}                   列出 Codex 全部版本及发布时间
  ${CYAN}codex-v-r <版本>${NC}            卸载指定 Codex 版本
  ${CYAN}codex-auto${NC}                  当前全局版本跳过审批与沙箱运行
  ${CYAN}codex-install <版本>${NC}        安装指定 Codex 版本
  ${CYAN}codex-current${NC}               显示当前系统 Codex 版本
  ${CYAN}codex-uninstall <版本>${NC}      卸载指定 Codex 版本
  ${CYAN}codex-remove <版本>${NC}         等同 codex-uninstall
  ${CYAN}codex-detect${NC}                检测 Codex 安装来源
  ${CYAN}codex-config${NC}                读取 Codex 配置文件信息

${BOLD}常用示例${NC}
  cvm use 2.1.90            # 临时使用 2.1.90 版本
  cvm pin 2.1.86 stable     # 收藏 2.1.86 并命名为 stable
  cvm pin 2.1.96            # 收藏 2.1.96
  cvm ls                    # 列出所有收藏版本
  cvm default 2.1.96        # 全局安装 2.1.96
  cvm uninstall 2.1.90      # 卸载本地所有 2.1.90
  cvm config set claude api-url https://api.example.com
  cvm config set claude api-key sk-ant-...
  cvm config set claude model claude-opus-4-7
  cvm menu                  # 交互式配置
  codex-v 0.139.0           # 运行 Codex 0.139.0
  cvm remote                # 查看最近发布的版本
  claude-v-l               # 查看所有版本及发布时间

"
}

# List pinned versions
cvm_list() {
  _cvm_ensure_dir
  local current
  current=$(_cvm_current_version)

  echo -e "\n${BOLD}📦 CVM - 已收藏的 Claude Code 版本${NC}"
  echo -e "───────────────────────────────────────────"

  if [[ ! -s "$CVM_PINS_FILE" ]]; then
    echo -e "  ${DIM}(空) 使用 ${CYAN}cvm pin <version>${NC}${DIM} 添加版本${NC}"
  else
    local has_entry=false
    while IFS='|' read -r ver alias_name note; do
      [[ -z "$ver" ]] && continue
      has_entry=true
      local marker=" "
      local ver_display="${GREEN}${ver}${NC}"
      if [[ "$ver" == "$current" ]]; then
        marker="${GREEN}▸${NC}"
        ver_display="${GREEN}${BOLD}${ver}${NC} ${GREEN}(当前)${NC}"
      fi
      if [[ -n "$alias_name" ]]; then
        printf "  %b %-22b %b\n" "$marker" "$ver_display" "${CYAN}← ${alias_name}${NC}"
      else
        printf "  %b %b\n" "$marker" "$ver_display"
      fi
    done < "$CVM_PINS_FILE"
    if ! $has_entry; then
      echo -e "  ${DIM}(空) 使用 ${CYAN}cvm pin <version>${NC}${DIM} 添加版本${NC}"
    fi
  fi

  echo -e "───────────────────────────────────────────"
  if [[ -n "$current" ]]; then
    echo -e "  全局版本: ${BOLD}${current}${NC}"
  else
    echo -e "  全局版本: ${DIM}未安装${NC}"
  fi
  echo -e "───────────────────────────────────────────"
  echo -e "  ${DIM}cvm use <版本>  临时运行  │  cvm pin <版本>  收藏${NC}"
  echo ""
}

# Install a specific version
cvm_install() {
  local ver="$1"

  if [[ -z "$ver" ]]; then
    _cvm_err "请指定版本号。例如: ${CYAN}cvm install 2.1.90${NC}"
    return 1
  fi

  _cvm_install_version "$ver"
}

# Uninstall a version from every local source managed or discovered by CVM
cvm_uninstall() {
  local ver="$1"
  local removed=false
  local dir package_json cached_ver global_root global_package_json global_ver tmpfile

  if [[ -z "$ver" ]]; then
    _cvm_err "请指定版本号。例如: ${CYAN}cvm uninstall 2.1.90${NC}"
    return 1
  fi
  if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    _cvm_err "版本格式无效: ${ver}"
    return 1
  fi

  _cvm_ensure_dir

  if [[ -d "$CVM_VERSIONS_DIR/$ver" ]]; then
    rm -rf "$CVM_VERSIONS_DIR/$ver"
    _cvm_log "已删除 CVM 安装 ${GREEN}v${ver}${NC}"
    removed=true
  fi
  while IFS= read -r dir; do
    rm -rf "$dir"
    removed=true
  done < <(find "$CVM_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d \
    \( -name ".${ver}.tmp.*" -o -name ".${ver}.cache.*" -o \
    -name ".${ver}.global.*" -o -name ".${ver}.incomplete.*" \) 2>/dev/null)

  while IFS= read -r package_json; do
    cached_ver=$(node -p "require('$package_json').version" 2>/dev/null)
    [[ "$cached_ver" == "$ver" ]] || continue
    dir="${package_json%/node_modules/$CVM_NPM_PACKAGE/package.json}"
    rm -rf "$dir"
    _cvm_log "已删除 npx 缓存 ${GREEN}v${ver}${NC}"
    removed=true
  done < <(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  global_root=$(npm root -g 2>/dev/null)
  global_package_json="$global_root/$CVM_NPM_PACKAGE/package.json"
  if [[ -f "$global_package_json" ]]; then
    global_ver=$(node -p "require('$global_package_json').version" 2>/dev/null)
    if [[ "$global_ver" == "$ver" ]]; then
      _cvm_info "正在卸载全局 npm 版本 ${GREEN}v${ver}${NC} ..."
      if npm uninstall -g "$CVM_NPM_PACKAGE"; then
        _cvm_log "已卸载全局 npm 版本 ${GREEN}v${ver}${NC}"
        removed=true
      else
        _cvm_err "全局 npm 版本 v${ver} 卸载失败"
        return 1
      fi
    fi
  fi

  if [[ -s "$CVM_PINS_FILE" ]]; then
    tmpfile=$(mktemp)
    while IFS='|' read -r v a n; do
      [[ "$v" == "$ver" ]] && continue
      echo "${v}|${a}|${n}" >> "$tmpfile"
    done < "$CVM_PINS_FILE"
    mv "$tmpfile" "$CVM_PINS_FILE"
  fi

  if $removed; then
    _cvm_log "Claude Code ${GREEN}v${ver}${NC} 已从本机卸载"
  else
    _cvm_warn "未找到 Claude Code v${ver} 的本地安装或缓存"
  fi
}

# Use a specific version, installing it first when necessary
cvm_use() {
  local ver="$1"
  shift

  if [[ -z "$ver" ]]; then
    _cvm_err "请指定版本号。例如: ${CYAN}cvm use 2.1.90${NC}"
    return 1
  fi

  # If it's an alias, resolve it
  local resolved
  resolved=$(_cvm_resolve_alias "$ver")
  if [[ -n "$resolved" ]]; then
    _cvm_info "别名 ${CYAN}${ver}${NC} → ${GREEN}${resolved}${NC}"
    ver="$resolved"
  fi

  _cvm_install_version "$ver" || return 1
  _cvm_info "启动 Claude Code ${GREEN}v${ver}${NC} ..."
  "$(_cvm_version_entry "$ver")" "$@"
}

# Pin a version
cvm_pin() {
  local ver="$1"
  local alias_name="$2"

  if [[ -z "$ver" ]]; then
    _cvm_err "请指定版本号。例如: ${CYAN}cvm pin 2.1.90${NC}"
    return 1
  fi

  _cvm_check_npm || return 1
  _cvm_ensure_dir

  # Validate version exists
  _cvm_info "检查版本 ${ver} ..."
  if ! _cvm_version_exists "$ver"; then
    _cvm_err "版本 ${ver} 不存在。使用 ${CYAN}cvm remote${NC} 查看可用版本"
    return 1
  fi

  # Remove old entry for same version or alias
  local tmpfile
  tmpfile=$(mktemp)
  while IFS='|' read -r v a n; do
    [[ "$v" == "$ver" ]] && continue
    [[ -n "$alias_name" && "$a" == "$alias_name" ]] && continue
    echo "${v}|${a}|${n}" >> "$tmpfile"
  done < "$CVM_PINS_FILE"
  mv "$tmpfile" "$CVM_PINS_FILE"

  # Add new entry
  echo "${ver}|${alias_name}|" >> "$CVM_PINS_FILE"

  # Sort pins by version
  sort -t'.' -k1,1n -k2,2n -k3,3n "$CVM_PINS_FILE" -o "$CVM_PINS_FILE"

  if [[ -n "$alias_name" ]]; then
    _cvm_log "已收藏 ${GREEN}v${ver}${NC} (别名: ${CYAN}${alias_name}${NC})"
  else
    _cvm_log "已收藏 ${GREEN}v${ver}${NC}"
  fi
}

# Unpin a version
cvm_unpin() {
  local target="$1"

  if [[ -z "$target" ]]; then
    _cvm_err "请指定版本号或别名。例如: ${CYAN}cvm unpin 2.1.90${NC}"
    return 1
  fi

  _cvm_ensure_dir

  local tmpfile found=false
  tmpfile=$(mktemp)
  while IFS='|' read -r v a n; do
    if [[ "$v" == "$target" || "$a" == "$target" ]]; then
      found=true
      continue
    fi
    echo "${v}|${a}|${n}" >> "$tmpfile"
  done < "$CVM_PINS_FILE"
  mv "$tmpfile" "$CVM_PINS_FILE"

  if $found; then
    _cvm_log "已移除 ${target}"
  else
    _cvm_err "未找到 ${target}"
    return 1
  fi
}

# Resolve alias to version
_cvm_resolve_alias() {
  local target="$1"
  _cvm_ensure_dir
  while IFS='|' read -r v a n; do
    if [[ "$a" == "$target" ]]; then
      echo "$v"
      return 0
    fi
  done < "$CVM_PINS_FILE"
  return 1
}

# Set default global version
cvm_default() {
  local ver="$1"

  if [[ -z "$ver" ]]; then
    _cvm_err "请指定版本号。例如: ${CYAN}cvm default 2.1.96${NC}"
    return 1
  fi

  # Resolve alias
  local resolved
  resolved=$(_cvm_resolve_alias "$ver")
  if [[ -n "$resolved" ]]; then
    _cvm_info "别名 ${CYAN}${ver}${NC} → ${GREEN}${resolved}${NC}"
    ver="$resolved"
  fi

  _cvm_check_npm || return 1

  _cvm_info "全局安装 Claude Code ${GREEN}v${ver}${NC} ..."
  npm install -g "${CVM_NPM_PACKAGE}@${ver}"

  if [[ $? -eq 0 ]]; then
    _cvm_log "全局默认版本已设置为 ${GREEN}v${ver}${NC}"
  else
    _cvm_err "安装失败"
    return 1
  fi
}

# Show current version
cvm_current() {
  local ver
  ver=$(_cvm_current_version)
  if [[ -n "$ver" ]]; then
    echo -e "当前全局版本: ${GREEN}${BOLD}v${ver}${NC}"
  else
    echo -e "当前全局版本: ${DIM}未安装${NC}"
    _cvm_info "使用 ${CYAN}cvm default <version>${NC} 安装"
  fi
}

# List remote versions
cvm_remote() {
  _cvm_check_npm || return 1

  local show_all=false
  [[ "$1" == "--all" || "$1" == "-a" ]] && show_all=true

  _cvm_info "从 npm 获取版本列表..."

  if $show_all; then
    npm view "$CVM_NPM_PACKAGE" versions --json 2>/dev/null | \
      node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const parsed = JSON.parse(input);
  const versions = Array.isArray(parsed) ? parsed : [parsed];
  versions.forEach(version => console.log(version));
});
'
  else
    echo -e "\n${BOLD}最近发布的 20 个版本:${NC}"
    echo -e "───────────────────────────────────────────"
    npm view "$CVM_NPM_PACKAGE" versions --json 2>/dev/null | \
      node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const parsed = JSON.parse(input);
  const versions = Array.isArray(parsed) ? parsed : [parsed];
  versions.slice(-20).forEach(version => console.log(`  ${version}`));
});
'
    echo -e "───────────────────────────────────────────"
    echo -e "  ${DIM}使用 ${CYAN}cvm remote --all${NC}${DIM} 查看全部版本${NC}"
    echo ""
  fi
}

# List all published versions and release times
cvm_releases() {
  _cvm_check_npm || return 1

  local registry="https://registry.npmjs.org"
  local time_json

  _cvm_info "从 npm 获取全部版本及发布时间..."
  if ! time_json=$(npm view "$CVM_NPM_PACKAGE" time --json --registry="$registry" 2>/dev/null); then
    _cvm_err "获取版本发布时间失败，请检查网络连接"
    return 1
  fi

  echo -e "\n${BOLD}Claude Code 全部版本:${NC}"
  echo -e "───────────────────────────────────────────"
  printf '%s' "$time_json" | node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  let times;
  try {
    times = JSON.parse(input);
  } catch {
    console.error("版本发布时间数据解析失败");
    process.exitCode = 1;
    return;
  }

  const rows = Object.entries(times)
    .filter(([version]) => /^\d+\.\d+\.\d+(?:[-+].+)?$/.test(version))
    .sort((a, b) => new Date(b[1]) - new Date(a[1]));

  const formatter = new Intl.DateTimeFormat("zh-CN", {
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false
  });

  for (const [version, publishedAt] of rows) {
    const localTime = formatter.format(new Date(publishedAt)).replace(/\//g, "-");
    console.log(`  ${version.padEnd(18)} ${localTime}`);
  }
  console.log(`\n共 ${rows.length} 个版本`);
});
'
  local result_code=$?
  echo -e "───────────────────────────────────────────"
  return $result_code
}

# List versions available from CVM, global npm, and runnable npx caches
cvm_installed() {
  _cvm_ensure_dir

  echo -e "\n${BOLD}Claude Code 本地可用版本:${NC}"
  echo -e "───────────────────────────────────────────"

  local records dir ver package_json bin_path entry global_root
  records=$(mktemp)

  while IFS= read -r dir; do
    ver="$(basename "$dir")"
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if _cvm_version_installed "$ver"; then
      printf '%s|CVM\n' "$ver" >> "$records"
    fi
  done < <(find "$CVM_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

  global_root=$(npm root -g 2>/dev/null)
  package_json="$global_root/$CVM_NPM_PACKAGE/package.json"
  if [[ -f "$package_json" ]]; then
    ver=$(node -p "require('$package_json').version" 2>/dev/null)
    entry="$global_root/$CVM_NPM_PACKAGE/$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.claude" 2>/dev/null)"
    if [[ -n "$ver" && -x "$entry" ]] &&
      [[ "$("$entry" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" == "$ver" ]]; then
      printf '%s|全局 npm\n' "$ver" >> "$records"
    fi
  fi

  while IFS= read -r package_json; do
    ver=$(node -p "require('$package_json').version" 2>/dev/null)
    bin_path=$(node -p "const p=require('$package_json'); typeof p.bin === 'string' ? p.bin : p.bin.claude" 2>/dev/null)
    entry="$(dirname "$package_json")/$bin_path"
    [[ -n "$ver" && -n "$bin_path" && -x "$entry" ]] || continue
    if [[ "$("$entry" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" == "$ver" ]]; then
      printf '%s|npx 缓存\n' "$ver" >> "$records"
    fi
  done < <(find "$HOME/.npm/_npx" -path "*/node_modules/$CVM_NPM_PACKAGE/package.json" -type f 2>/dev/null)

  if [[ ! -s "$records" ]]; then
    echo -e "  ${DIM}(暂无本地可用版本)${NC}"
  else
    sort -t'|' -k1,1V -k2,2 -u "$records" | awk -F'|' '
      function flush() {
        if (version != "") printf "  \033[0;32m✔\033[0m %-12s \033[2m%s\033[0m\n", version, sources
      }
      {
        if ($1 != version) {
          flush()
          version = $1
          sources = $2
        } else {
          sources = sources " / " $2
        }
      }
      END { flush() }
    '
  fi
  rm -f "$records"
  echo -e "───────────────────────────────────────────\n"
}

# Update global installation
cvm_update() {
  _cvm_check_npm || return 1

  local before
  before=$(_cvm_current_version)
  _cvm_info "更新全局 Claude Code ..."
  npm update -g "$CVM_NPM_PACKAGE"

  local after
  after=$(_cvm_current_version)

  if [[ "$before" == "$after" ]]; then
    _cvm_log "已是最新版本 ${GREEN}v${after}${NC}"
  else
    _cvm_log "已更新: ${YELLOW}v${before}${NC} → ${GREEN}v${after}${NC}"
  fi
}

# Clean npx cache
cvm_clean() {
  _cvm_info "清理 npm/npx 缓存..."
  npm cache clean --force 2>/dev/null
  _cvm_log "缓存已清理"
}

# Doctor - diagnose environment
cvm_doctor() {
  echo -e "\n${BOLD}🔍 CVM 环境诊断${NC}"
  echo -e "───────────────────────────────────────────"

  # Node.js
  if command -v node &>/dev/null; then
    echo -e "  ${GREEN}✔${NC} Node.js  $(node --version)"
  else
    echo -e "  ${RED}✖${NC} Node.js  未安装"
  fi

  # npm
  if command -v npm &>/dev/null; then
    echo -e "  ${GREEN}✔${NC} npm      v$(npm --version)"
  else
    echo -e "  ${RED}✖${NC} npm      未安装"
  fi

  # npx
  if command -v npx &>/dev/null; then
    echo -e "  ${GREEN}✔${NC} npx      可用"
  else
    echo -e "  ${RED}✖${NC} npx      未安装"
  fi

  # Claude Code global
  local ver
  ver=$(_cvm_current_version)
  if [[ -n "$ver" ]]; then
    echo -e "  ${GREEN}✔${NC} claude   v${ver} ($(which claude))"
  else
    echo -e "  ${YELLOW}⚠${NC} claude   未全局安装"
  fi

  # CVM data directory
  if [[ -d "$CVM_DIR" ]]; then
    local pin_count
    pin_count=$(grep -c '.' "$CVM_PINS_FILE" 2>/dev/null || echo 0)
    echo -e "  ${GREEN}✔${NC} CVM 数据 ${CVM_DIR} (${pin_count} 个收藏版本)"
  else
    echo -e "  ${YELLOW}⚠${NC} CVM 数据 目录未创建"
  fi

  echo -e "───────────────────────────────────────────\n"
}

cvm_self_update() {
  local source_url temp_file
  source_url="https://raw.githubusercontent.com/${CVM_REPO}/main/src/cvm.sh"
  temp_file=$(mktemp)

  _cvm_info "从 ${CVM_REPO} 获取最新 CVM ..."
  if ! curl --fail --location --silent --show-error "$source_url" --output "$temp_file"; then
    rm -f "$temp_file"
    _cvm_err "CVM 更新下载失败"
    return 1
  fi
  if ! bash -n "$temp_file"; then
    rm -f "$temp_file"
    _cvm_err "下载的 CVM 脚本语法校验失败"
    return 1
  fi
  if command -v zsh &>/dev/null && ! zsh -n "$temp_file"; then
    rm -f "$temp_file"
    _cvm_err "下载的 CVM 脚本语法校验失败"
    return 1
  fi

  mkdir -p "$CVM_DIR"
  [[ -f "$CVM_DIR/cvm.sh" ]] && cp "$CVM_DIR/cvm.sh" "$CVM_DIR/cvm.sh.bak"
  mv "$temp_file" "$CVM_DIR/cvm.sh"
  chmod 0644 "$CVM_DIR/cvm.sh"
  _cvm_log "CVM 已更新，请执行 ${CYAN}source ~/.cvm/cvm.sh${NC} 或重开终端"
}

# View changelog for a version
cvm_changelog() {
  local ver="${1:-}"
  if [[ -z "$ver" ]]; then
    ver=$(_cvm_current_version)
    if [[ -z "$ver" ]]; then
      _cvm_err "请指定版本号。例如: ${CYAN}cvm changelog 2.1.90${NC}"
      return 1
    fi
  fi

  _cvm_info "打开 v${ver} 更新日志..."
  local url="https://github.com/anthropics/claude-code/releases/tag/v${ver}"

  if command -v open &>/dev/null; then
    open "$url"
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$url"
  elif command -v explorer.exe &>/dev/null; then
    explorer.exe "$url"
  else
    echo -e "  ${CYAN}${url}${NC}"
  fi
}

# ── Main Entry ───────────────────────────────────────────────────────────────

cvm() {
  local cmd="${1:-}"
  shift 2>/dev/null

  case "$cmd" in
    codex)      _cvm_codex_command "$@" ;;
    use)        cvm_use "$@" ;;
    install)    cvm_install "$@" ;;
    uninstall|remove|rm) cvm_uninstall "$@" ;;
    pin)        cvm_pin "$@" ;;
    unpin)      cvm_unpin "$@" ;;
    default)    cvm_default "$@" ;;
    list|ls)    cvm_list "$@" ;;
    current)    cvm_current "$@" ;;
    installed)  cvm_installed "$@" ;;
    remote)     cvm_remote "$@" ;;
    releases)   cvm_releases "$@" ;;
    self-update) cvm_self_update "$@" ;;
    update)     cvm_update "$@" ;;
    clean)      cvm_clean "$@" ;;
    doctor)     cvm_doctor "$@" ;;
    detect)     cvm_detect "$@" ;;
    config)     cvm_config "$@" ;;
    menu)       cvm_menu "$@" ;;
    changelog)  cvm_changelog "$@" ;;
    version|-v) echo "cvm v${CVM_VERSION}" ;;
    help|-h|--help|"")
      cvm_help
      ;;
    *)
      # Check if it looks like a version number
      if [[ "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        cvm_use "$cmd" "$@"
      else
        _cvm_err "未知命令: ${cmd}"
        echo -e "  使用 ${CYAN}cvm help${NC} 查看帮助"
        return 1
      fi
      ;;
  esac
}

# Run the globally configured Claude Code with permission prompts bypassed.
claude-auto() {
  claude --permission-mode bypassPermissions "$@"
}

claude-v() {
  if [[ -z "$1" ]]; then
    claude --version
    return $?
  fi
  cvm_use "$@"
}

claude-latest() {
  npx --yes --registry="$CVM_REGISTRY" "${CVM_NPM_PACKAGE}@latest" "$@"
}

claude-versions() {
  npm view "$CVM_NPM_PACKAGE" versions --registry="$CVM_REGISTRY"
}

claude-clean() {
  cvm_clean
}

claude-update() {
  cvm_update
}

claude-detect() {
  cvm_detect claude
}

claude-config() {
  cvm_config claude
}

claude-install() {
  cvm_install "$@"
}

claude-current() {
  cvm_current "$@"
}

claude-uninstall() {
  cvm_uninstall "$@"
}

claude-remove() {
  cvm_uninstall "$@"
}

# List all Claude Code versions and their publication times.
claude-v-l() {
  cvm_releases "$@"
}

claude-l-l() {
  cvm_releases "$@"
}

# List all locally installed Claude Code versions.
claude-v-a() {
  cvm_installed "$@"
}

claude-l-a() {
  cvm_installed "$@"
}

# Uninstall a specific Claude Code version.
claude-v-r() {
  cvm_uninstall "$@"
}

claude-l-r() {
  cvm_uninstall "$@"
}

# Codex version shortcuts.
codex-auto() {
  codex --dangerously-bypass-approvals-and-sandbox "$@"
}

codex-v() {
  if [[ -z "$1" ]]; then
    codex --version
    return $?
  fi
  _cvm_codex_use "$@"
}

codex-v-a() {
  _cvm_codex_installed
}

codex-l-a() {
  _cvm_codex_installed
}

codex-v-l() {
  _cvm_codex_releases
}

codex-l-l() {
  _cvm_codex_releases
}

codex-v-r() {
  _cvm_codex_uninstall "$@"
}

codex-l-r() {
  _cvm_codex_uninstall "$@"
}

codex-latest() {
  npx --yes --registry="$CVM_REGISTRY" "${CVM_CODEX_NPM_PACKAGE}@latest" "$@"
}

codex-versions() {
  npm view "$CVM_CODEX_NPM_PACKAGE" versions --registry="$CVM_REGISTRY"
}

codex-clean() {
  cvm_clean
}

codex-detect() {
  cvm_detect codex
}

codex-config() {
  cvm_config codex
}

codex-update() {
  local current_entry
  current_entry=$(command -v codex 2>/dev/null)
  if command -v brew &>/dev/null &&
    [[ "$current_entry" == /opt/homebrew/*/codex || "$current_entry" == /usr/local/*/codex ]]; then
    brew upgrade --cask codex
  else
    npm install -g "${CVM_CODEX_NPM_PACKAGE}@latest" --registry="$CVM_REGISTRY"
  fi
  codex --version
}

codex-install() {
  _cvm_codex_install_version "$@"
}

codex-current() {
  codex --version "$@"
}

codex-uninstall() {
  _cvm_codex_uninstall "$@"
}

codex-remove() {
  _cvm_codex_uninstall "$@"
}

# Run any Claude Code or Codex version via versioned commands.
if [[ -n "$ZSH_VERSION" ]]; then
  if (( $+functions[command_not_found_handler] )); then
    functions[_cvm_previous_command_not_found_handler]=$functions[command_not_found_handler]
  fi

  command_not_found_handler() {
    local command_name="$1"
    shift

    if [[ "$command_name" =~ '^claude-auto-([0-9]+\.[0-9]+\.[0-9]+)$' ]]; then
      cvm_use "${match[1]}" --permission-mode bypassPermissions "$@"
      return $?
    fi

    if [[ "$command_name" =~ '^claude-([0-9]+\.[0-9]+\.[0-9]+)$' ]]; then
      cvm_use "${match[1]}" "$@"
      return $?
    fi

    if [[ "$command_name" =~ '^codex-([0-9]+\.[0-9]+\.[0-9]+)$' ]]; then
      _cvm_codex_use "${match[1]}" "$@"
      return $?
    fi

    if [[ "$command_name" =~ '^codex-auto-([0-9]+\.[0-9]+\.[0-9]+)$' ]]; then
      _cvm_codex_use "${match[1]}" --dangerously-bypass-approvals-and-sandbox "$@"
      return $?
    fi

    if (( $+functions[_cvm_previous_command_not_found_handler] )); then
      _cvm_previous_command_not_found_handler "$command_name" "$@"
      return $?
    fi

    print -u2 "zsh: command not found: $command_name"
    return 127
  }
elif [[ -n "$BASH_VERSION" ]]; then
  if declare -F command_not_found_handle >/dev/null 2>&1; then
    eval "$(declare -f command_not_found_handle | sed '1s/command_not_found_handle/_cvm_previous_command_not_found_handle/')"
  fi

  command_not_found_handle() {
    local command_name="$1"
    shift

    if [[ "$command_name" =~ ^claude-auto-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      cvm_use "${BASH_REMATCH[1]}" --permission-mode bypassPermissions "$@"
      return $?
    fi

    if [[ "$command_name" =~ ^claude-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      cvm_use "${BASH_REMATCH[1]}" "$@"
      return $?
    fi

    if [[ "$command_name" =~ ^codex-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      _cvm_codex_use "${BASH_REMATCH[1]}" "$@"
      return $?
    fi

    if [[ "$command_name" =~ ^codex-auto-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      _cvm_codex_use "${BASH_REMATCH[1]}" --dangerously-bypass-approvals-and-sandbox "$@"
      return $?
    fi

    if declare -F _cvm_previous_command_not_found_handle >/dev/null 2>&1; then
      _cvm_previous_command_not_found_handle "$command_name" "$@"
      return $?
    fi

    printf 'bash: %s: command not found\n' "$command_name" >&2
    return 127
  }
fi

# ── Tab Completion ───────────────────────────────────────────────────────────

_cvm_completions() {
  local commands="codex use install uninstall remove rm pin unpin default list ls current installed remote releases self-update update clean doctor detect config menu changelog version help"

  if [[ ${#COMP_WORDS[@]} -eq 2 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "${COMP_WORDS[1]}"))
  elif [[ ${#COMP_WORDS[@]} -eq 3 ]]; then
    case "${COMP_WORDS[1]}" in
      use|uninstall|remove|rm|unpin)
        # Complete with pinned versions and aliases
        local pins=""
        if [[ -f "$CVM_PINS_FILE" ]]; then
          while IFS='|' read -r v a n; do
            [[ -n "$v" ]] && pins+="$v "
            [[ -n "$a" ]] && pins+="$a "
          done < "$CVM_PINS_FILE"
        fi
        COMPREPLY=($(compgen -W "$pins" -- "${COMP_WORDS[2]}"))
        ;;
    esac
  fi
}

# Zsh completion
if [[ -n "$ZSH_VERSION" ]] && (( $+functions[compdef] )); then
  _cvm_zsh_completions() {
    local commands=(
      'codex:管理 Codex CLI 版本'
      'use:使用指定版本启动 Claude Code'
      'install:安装指定版本'
      'uninstall:卸载指定版本'
      'remove:卸载指定版本'
      'rm:卸载指定版本'
      'pin:收藏一个版本'
      'unpin:移除收藏的版本'
      'default:设置全局默认版本'
      'list:列出已收藏的版本'
      'ls:列出已收藏的版本'
      'current:显示当前全局版本'
      'remote:列出可用的远程版本'
      'releases:列出所有版本及发布时间'
      'self-update:更新 CVM 管理脚本'
      'update:更新全局安装'
      'clean:清理缓存'
      'doctor:诊断环境'
      'detect:检测安装来源'
      'config:读取或编辑配置'
      'menu:打开交互式菜单'
      'changelog:查看更新日志'
      'version:显示 CVM 版本'
      'help:显示帮助'
    )

    if (( CURRENT == 2 )); then
      _describe 'cvm commands' commands
    elif (( CURRENT == 3 )); then
      case "${words[2]}" in
        use|uninstall|remove|rm|unpin)
          local -a pins=()
          if [[ -f "$CVM_PINS_FILE" ]]; then
            while IFS='|' read -r v a n; do
              [[ -n "$v" ]] && pins+=("$v")
              [[ -n "$a" ]] && pins+=("$a")
            done < "$CVM_PINS_FILE"
          fi
          _describe 'versions' pins
          ;;
      esac
    fi
  }
  compdef _cvm_zsh_completions cvm
elif [[ -n "$BASH_VERSION" ]]; then
  complete -F _cvm_completions cvm
fi
