# Claude Codex Version Manager

`cvm` 是面向 macOS 的 Claude Code 与 OpenAI Codex CLI 版本管理工具。

它可以复用已有的 CVM 安装、npm/npx 缓存、全局 npm 安装以及 Homebrew
Codex，只有本地不存在目标版本时才联网下载。

## 要求

- macOS
- zsh
- Node.js 与 npm
- curl

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DoBestone/claude-codex-version-manager/main/install.sh)
source ~/.zshrc
```

安装器可以重复执行。升级时仅替换 `~/.cvm/cvm.sh`，不会删除已安装版本、
收藏或缓存导入结果。

本地克隆安装：

```bash
git clone https://github.com/DoBestone/claude-codex-version-manager.git
cd claude-codex-version-manager
bash install.sh
source ~/.zshrc
```

## Claude Code

```bash
claude-2.1.177        # 安装或复用后运行指定版本
claude-v 2.1.177      # 同上
claude-l-a            # 本地可用版本
claude-l-l            # 版本及发布时间
claude-l-r 2.1.177    # 卸载指定版本
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
codex-latest          # 临时运行 npm 最新版
codex-versions        # npm 全部版本
codex-update          # 按当前来源使用 Homebrew 或 npm 更新
```

`codex-v-a`、`codex-v-l`、`codex-v-r` 保留为兼容别名。

Codex 的卸载不会删除 Homebrew 系统安装，只清理 CVM 副本与匹配的 npx
缓存。

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
