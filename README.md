<div align="center">

# BazaarPlusPlus

**因热爱而生** · 为 [《The Bazaar》](https://www.playthebazaar.com) 打造的 BepInEx 模组与桌面安装器

[English](README_en.md) · [官网](https://bazaarplusplus.com)

[![Version](https://img.shields.io/badge/version-4.2.0-6dd9a0?style=flat-square)](https://bazaarplusplus.com)
[![License](https://img.shields.io/badge/license-MIT-e8c87a?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%28Proton%29-c1875a?style=flat-square)](https://bazaarplusplus.com/download)
[![BepInEx](https://img.shields.io/badge/BepInEx-5.x-8a6d3b?style=flat-square)](https://github.com/BepInEx/BepInEx)
[![.NET](https://img.shields.io/badge/.NET-Standard%202.1-512bd4?style=flat-square)](https://learn.microsoft.com/dotnet/standard/net-standard)
[![Tauri](https://img.shields.io/badge/Tauri-2.x-24c8d8?style=flat-square)](https://tauri.app)
[![React](https://img.shields.io/badge/React-19-61dafb?style=flat-square)](https://react.dev)

</div>

---

BazaarPlusPlus 是一个面向《The Bazaar》Linux/Proton 环境的开源项目：游戏内由 BepInEx 模组提供卡牌图鉴、对局历史、战斗回放、Tooltip 预览、匿名模式、中文术语等功能；仓库同时保留 Linux 直装所需的共享资源树与最小辅助工具。

本项目是 [BazaarPlusPlus](https://github.com/cauyxy/BazaarPlusPlus) 的分支；主要增加了对 Linux Steam 客户端的兼容性和从源码构建的流程。

> 项目代码主要由 [Codex](https://openai.com/codex) 主导，并由 [Claude Code](https://claude.com/product/claude-code) 协作完成。

## 快速开始

### Linux (Debian/Ubuntu)

如果只是想在 Proton 环境里直接安装，可以不构建 `.deb`，而是把所需文件直接复制到 Steam 游戏目录。

如果当前检出里已经包含完整的 Proton payload，可直接运行最短命令：

```bash
cd bazaarplusplus-mod
./run.sh install --skip-build
```

如果 payload 不存在、但机器上有 .NET SDK 8+ 和 Steam 版 The Bazaar，运行不带 `--skip-build` 的安装命令即可自动构建并安装：

```bash
cd bazaarplusplus-mod
./run.sh install --game-dir "/path/to/steamapps/common/The Bazaar"
```

也可以单独构建 payload 再安装：

```bash
cd bazaarplusplus-mod
./run.sh build-payload --game-dir "/path/to/steamapps/common/The Bazaar"
./run.sh install --skip-build
```

如果自动探测 Steam 游戏目录失败，可手动指定：

```bash
./run.sh install --game-dir "/path/to/steamapps/common/The Bazaar" --skip-build
```

在 Steam 中打开 **库** → 右键 **The Bazaar** → **属性** → **启动选项**，填入：

```bash
WINEDLLOVERRIDES="winhttp=n,b" %command%
```

启动一次游戏后，如需确认 BepInEx 是否正常加载，可执行：

```bash
./run.sh proton-log
```

## 功能概览

### 游戏内模组

- **卡牌图鉴**：在游戏中查阅物品和技能，按英雄、品质、体型、商人等维度过滤，还能跟随当前游戏天数查看可获取的内容。
- **BazaarDB 自动上传**：社区数据共建功能，在结算后于后台上传通关截图与阵容数据；默认关闭，需手动开启。
- **对局历史与战斗回放**：通过 `F8` 打开历史面板，浏览本地对局与关键战斗，观看战斗回放和幽灵对战。
- **战斗状态栏**：显示战斗时间与暂停状态，并提供速度控制，适合复盘、录制和直播。
- **匿名模式**：在截图、录制或直播时隐藏本地玩家名称。
- **传奇名次显示**：提供「无人知晓」（隐藏名次）、「战力爆表」、名次与分数双显等显示模式。
- **附魔与升级预览**：在物品 Tooltip 中直接预览附魔或升级后的效果。
- **中文术语模式**：支持简体中文、台湾繁体、香港繁体三种术语风格。

### Linux 安装与辅助资源

- **Linux Steam Proton 直装**：使用 `./run.sh install` 自动定位 Steam 版《The Bazaar》目录并复制所需 payload。
- **修复 / 重装辅助**：保留 Linux 直装所需的共享资源树，供 `run.sh install` 与相关工具复用。
- **直播资源**：保留直播叠层所需静态资源。

## 仓库结构

```
.
├── bazaarplusplus-mod/                       # BepInEx 模组源码
│   ├── run.sh                                # Linux build/install/format 入口
│   └── src/
│       ├── BazaarPlusPlus/                   # 主模组：Game、Patches、Resources、Data
│       ├── BazaarPlusPlus.ModApi/            # 与服务端通信的 API 客户端
│       ├── BazaarPlusPlus.Storage/           # 本地运行日志、截图和 SQLite 存储
│       └── BazaarPlusPlus.Localization/      # 中文术语与本地化引擎
└── bazaarplusplus-installer/                 # Linux 共享资源树与最小辅助工具
    ├── src/                                  # 如仍保留本地 Linux UI，则其前端代码在这里
    ├── src-tauri/                            # 最小 Linux Tauri 壳层与资源目录
    │   └── resources/                        # Proton payload、FFmpeg、直播叠层等共享资源
    ├── scripts/                              # bindings、prebuild 等辅助脚本
    └── build.sh                              # 本地 Linux dev/build 辅助入口
```

## 从源码构建

### 环境要求

- **模组**：.NET SDK 8+，以及本机 Steam 版《The Bazaar》（用于解析游戏程序集引用）。
- **安装器**：Node.js 20+、Rust 工具链、Tauri 系统依赖（见 [Tauri prerequisites](https://tauri.app/start/prerequisites/)）。
- **Linux**：需要 Steam Linux 客户端与 Proton 版《The Bazaar》用于本地测试。若使用 `./run.sh install --skip-build` 直装，当前检出还必须已经包含可复用的 Release 产物；如果没有，请在具备 .NET SDK 8+ 的环境中去掉 `--skip-build` 或先构建一次模组。若系统没有 `zip`，辅助脚本会尝试使用 `7z` 生成 Linux Proton payload 资源包。

### 构建模组

```bash
cd bazaarplusplus-mod

# 构建模组并刷新 installer 使用的 Proton payload（包含主插件和 BazaarAgent host）
./run.sh build-payload --game-dir "/path/to/steamapps/common/The Bazaar"

# 仅构建 Release 模组（不刷新 installer payload）
./run.sh build

# 显式指定游戏程序集目录
dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj \
  -c Release \
  -p:ManagedPath="<Steam>/steamapps/common/The Bazaar/.../Managed"
```

### 构建安装器

```bash
cd bazaarplusplus-mod
./run.sh build-payload --game-dir "/path/to/steamapps/common/The Bazaar"

cd ../bazaarplusplus-installer
npm install
npm run check
npm run test
npm run format

./build.sh --prod
```

`build-payload` 只刷新 installer 复用的 Proton mod payload，不生成 `.deb`。`./build.sh --prod` 会从该 payload 生成 Linux Proton 资源 zip 并构建本地 Linux app binary；不会生成 `.deb`。

## 二次开发须知

如果你计划基于本项目或本模组进行二次开发，请务必遵循《The Bazaar》官方 Mod Policy：

[The Bazaar Mod Policy](https://www.playthebazaar.com/mod-policy)

## 致谢

- **原项目**：[BazaarPlusPlus](https://github.com/cauyxy/BazaarPlusPlus)
- **灵感来源**：[BazaarHelper](https://github.com/Duangi/BazaarHelper)、[BazaarPlannerMod](https://github.com/oceanseth/BazaarPlannerMod)
- **数据来源**：[bazaardb.gg](https://bazaardb.gg)
- **运行依赖**：[BepInEx](https://github.com/BepInEx/BepInEx)、[Harmony](https://github.com/pardeike/Harmony)、[Tauri](https://tauri.app)、[React](https://react.dev)、[Vite](https://vite.dev)、[Tailwind CSS](https://tailwindcss.com)、[FFmpeg](https://ffmpeg.org)
- **字体**：[LXGW WenKai](https://github.com/lxgw/LxgwWenKai)（SIL Open Font License 1.1）
- **共创**：[Codex](https://openai.com/codex)、[Claude Code](https://claude.com/product/claude-code)

## License

本项目使用 [MIT License](LICENSE)。
