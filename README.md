# Claude Codex Version Manager

`cvm` 是面向 macOS、Linux 与 Windows bash 环境的 Claude Code 与
OpenAI Codex CLI 版本管理工具。

它可以复用已有的 CVM 安装、npm/npx 缓存、全局 npm 安装以及 macOS 上的
Homebrew Codex，只有本地不存在目标版本时才联网下载。

## 要求

- macOS、Linux，或 Windows 的 Git Bash/MSYS2/Cygwin
- bash 或 zsh
- Node.js 与 npm
- curl

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DoBestone/claude-codex-version-manager/main/install.sh)
source ~/.cvm/cvm.sh
```

安装器可以重复执行。升级时仅替换 `~/.cvm/cvm.sh`，不会删除已安装版本、
收藏或缓存导入结果。默认会按当前 shell 写入 `~/.zshrc`、`~/.bashrc` 或
`~/.profile`；也可以通过 `CVM_SHELL_RC=/path/to/rc bash install.sh` 指定。

本地克隆安装：

```bash
git clone https://github.com/DoBestone/claude-codex-version-manager.git
cd claude-codex-version-manager
bash install.sh
source ~/.cvm/cvm.sh
```

Windows 需在 Git Bash、MSYS2 或 Cygwin 中运行上述命令。当前不提供原生
PowerShell 安装器。

## Claude Code

```bash
claude-2.1.177        # 安装或复用后运行指定版本
claude-v 2.1.177      # 同上
claude-l-a            # 本地可用版本
claude-l-l            # 版本及发布时间
claude-l-r 2.1.177    # 卸载指定版本
claude-install 2.1.177 # 只安装指定版本
claude-current        # 当前系统版本
claude-uninstall 2.1.177
claude-remove 2.1.177 # uninstall 的别名
claude-auto           # 当前版本免权限确认运行
claude-auto-2.1.177   # 指定版本免权限确认运行
claude-latest         # 临时运行 npm 最新版
claude-versions       # npm 全部版本
claude-update         # 更新全局 Claude Code
```

`claude-v-a`、`claude-v-l`、`claude-v-r` 保留为兼容别名。

## Codex

```bash
codex-0.139.0         # 安装或复用后运行指定版本
codex-v 0.139.0       # 同上
codex-l-a             # 本地可用版本
codex-l-l             # 版本及发布时间
codex-l-r 0.139.0     # 卸载 CVM 副本和 npx 缓存
codex-install 0.139.0 # 只安装指定版本
codex-current         # 当前系统版本
codex-uninstall 0.139.0
codex-remove 0.139.0  # uninstall 的别名
codex-auto            # 当前版本跳过审批与沙箱运行
codex-auto-0.139.0    # 指定版本跳过审批与沙箱运行
codex-latest          # 临时运行 npm 最新版
codex-versions        # npm 全部版本
codex-update          # 按当前来源使用 Homebrew(macOS) 或 npm 更新
```

`codex-v-a`、`codex-v-l`、`codex-v-r` 保留为兼容别名。

Codex 的卸载不会删除 Homebrew 或 npm 的系统安装，只清理 CVM 副本与匹配的
npx 缓存。

`claude-auto*` 和 `codex-auto*` 会关闭对应 CLI 的安全确认，仅应在可信目录
和明确了解命令影响时使用。Codex 原生命令继续直接使用，例如
`codex exec`、`codex review`、`codex resume`、`codex mcp` 和 `codex plugin`。

## CVM 子命令

```bash
cvm doctor
cvm installed
cvm use 2.1.177
cvm install 2.1.177
cvm uninstall 2.1.177
cvm self-update

cvm codex installed
cvm codex use 0.139.0
cvm codex install 0.139.0
cvm codex uninstall 0.139.0
```

## 数据目录

```text
~/.cvm/
├── cvm.sh
├── pins
├── versions/
└── codex-versions/
```

## 卸载

保留已安装版本数据：

```bash
bash uninstall.sh
```

彻底删除：

```bash
bash uninstall.sh --purge
```

## 开发验证

```bash
bash tests/smoke.sh
shellcheck install.sh uninstall.sh tests/smoke.sh
```

## 说明

本项目不是 Anthropic 或 OpenAI 官方项目。Claude Code、Codex 及相关名称
归各自权利方所有。
