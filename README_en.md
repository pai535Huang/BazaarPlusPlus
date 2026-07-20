<div align="center">

# BazaarPlusPlus

**Born of Passion** · A BepInEx mod and desktop installer for [*The Bazaar*](https://www.playthebazaar.com)

[中文](README.md) · [Website](https://bazaarplusplus.com)

[![Version](https://img.shields.io/badge/version-4.6.0-6dd9a0?style=flat-square)](https://bazaarplusplus.com)
[![License](https://img.shields.io/badge/license-MIT-e8c87a?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%28Proton%29-c1875a?style=flat-square)](https://bazaarplusplus.com/download)
[![BepInEx](https://img.shields.io/badge/BepInEx-5.x-8a6d3b?style=flat-square)](https://github.com/BepInEx/BepInEx)
[![.NET](https://img.shields.io/badge/.NET-Standard%202.1-512bd4?style=flat-square)](https://learn.microsoft.com/dotnet/standard/net-standard)
[![Tauri](https://img.shields.io/badge/Tauri-2.x-24c8d8?style=flat-square)](https://tauri.app)
[![React](https://img.shields.io/badge/React-19-61dafb?style=flat-square)](https://react.dev)

</div>

---

BazaarPlusPlus is an open-source project for *The Bazaar* on Linux/Proton. The in-game BepInEx mod adds a card collection browser, run history, combat replays, tooltip previews, anonymous mode, Chinese terminology, and related quality-of-life features. This repo also keeps the shared resource tree and minimal helper tooling needed for Linux direct install.

This project is a fork of [BazaarPlusPlus](https://github.com/cauyxy/BazaarPlusPlus); it primarily adds Linux Steam client compatibility and source-build workflows.

> The bulk of the codebase is led by [Codex](https://openai.com/codex), with collaboration from [Claude Code](https://claude.com/product/claude-code).

## Quick Start

Feature guides, hotkeys, and installation details live at [bazaarplusplus.com/tutorial](https://bazaarplusplus.com/tutorial?lang=en).

### Linux (Debian/Ubuntu)

For a direct Proton install, you can copy the required files straight into the Steam game directory without building a `.deb` package.

If this checkout already contains a complete Proton payload, you can run the shortest command:

```bash
cd bazaarplusplus-mod
./run.sh install --skip-build
```

If the payload is not present but the machine has .NET SDK 8+ and a Steam install of The Bazaar, run without `--skip-build` to let the script build first and then install:

```bash
cd bazaarplusplus-mod
./run.sh install --game-dir "/path/to/steamapps/common/The Bazaar"
```

Or build the payload upfront, then install:

```bash
cd bazaarplusplus-mod
./run.sh build-payload --game-dir "/path/to/steamapps/common/The Bazaar"
./run.sh install --skip-build
```

If automatic Steam detection fails, point it at the game directory explicitly:

```bash
./run.sh install --game-dir "/path/to/steamapps/common/The Bazaar" --skip-build
```

In Steam, open **Library** → right-click **The Bazaar** → **Properties** → **Launch Options**, then set:

```bash
WINEDLLOVERRIDES="winhttp=n,b" %command%
```

Launch the game once, then optionally verify the BepInEx log:

```bash
./run.sh proton-log
```

## Feature Overview

### In-Game Mod

- **Card Collection**: Browse items and skills in-game, with filters for hero, tier, size, merchant, and current run day.
- **BazaarDB Auto Upload**: Community-data contribution that uploads end-of-run screenshots and board data in the background. Disabled by default; opt-in only.
- **Run History and Combat Replay**: Press `F8` to browse past runs and key fights, and watch replays and ghost battles.
- **Combat Status Bar**: Shows combat time and pause state, with speed controls — handy for review, recording, and streaming.
- **Anonymous Mode**: Hide the local player name in screenshots, recordings, and streams.
- **Legendary Rank Display**: Hide your rank, show an exaggerated power value, or display rank and rating together.
- **Enchant and Upgrade Previews**: Preview post-enchant or post-upgrade item values directly in tooltips.
- **Chinese Terminology Modes**: Simplified Chinese plus Taiwan and Hong Kong Traditional terminology styles.

### Linux install and shared resources

- **Linux Steam Proton direct install**: Use `./run.sh install` to auto-detect the Steam game directory and copy the required Proton payload.
- **Repair / reinstall support**: The repo keeps the shared resource tree that `run.sh install` and related helpers reuse.
- **Stream assets**: Stream overlay static assets are kept in-tree for Linux use.

## Repository Layout

```
.
├── bazaarplusplus-mod/                       # BepInEx mod source
│   ├── run.sh                                # Linux build/install/format entry point
│   └── src/
│       ├── BazaarPlusPlus/                   # Main mod: Game, Patches, Resources, Data
│       ├── BazaarPlusPlus.ModApi/            # HTTP client for the mod backend
│       ├── BazaarPlusPlus.Storage/           # Local run logs, screenshots, and SQLite storage
│       └── BazaarPlusPlus.Localization/      # Chinese terminology and localization engine
└── bazaarplusplus-installer/                 # Linux shared resources and minimal helper tooling
    ├── src/                                  # If a local Linux UI is still kept, its frontend code lives here
    ├── src-tauri/                            # Minimal Linux Tauri shell and resource directory
    │   └── resources/                        # Proton payload, FFmpeg, stream overlay, and other shared assets
    ├── scripts/                              # Binding and prebuild helper scripts
    └── build.sh                              # Local Linux dev/build helper entry point
```

## Building From Source

### Prerequisites

- **Mod**: .NET SDK 8+ and a local Steam install of *The Bazaar* so game assemblies can be resolved.
- **Installer**: Node.js 20+, the Rust toolchain, and the system dependencies listed in the [Tauri prerequisites](https://tauri.app/start/prerequisites/).
- **Linux**: The Steam Linux client and a Proton install of *The Bazaar* are needed for local testing. If you use `./run.sh install --skip-build` for a direct install, the current checkout must also already contain reusable Release artifacts; otherwise, remove `--skip-build` in an environment that has .NET SDK 8+, or build the mod once beforehand. If `zip` is unavailable, the helper scripts fall back to `7z` when creating the Linux Proton payload resource archive.

### Build the Mod

```bash
cd bazaarplusplus-mod

# Build the mod and refresh the Proton payload (main plugin plus BazaarAgent host)
./run.sh build-payload --game-dir "/path/to/steamapps/common/The Bazaar"

# Build only the Release mod (without refreshing the installer payload)
./run.sh build

# Override the game assembly directory explicitly
dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj \
  -c Release \
  -p:ManagedPath="<Steam>/steamapps/common/The Bazaar/.../Managed"
```

### Build the Installer

```bash
cd bazaarplusplus-mod
./run.sh build-payload --game-dir "/path/to/steamapps/common/The Bazaar"

cd ../bazaarplusplus-installer

npm install
npm run dev        # Vite frontend dev server
npm run tauri dev  # full Tauri desktop app

npm run check
npm run test
npm run format

./build.sh --prod  # refresh the Linux Proton resource zip and build the local Linux app binary
```

`build-payload` only refreshes the Proton mod payload reused by the installer; it does not produce a `.deb` package. The installer helper script syncs versions, runs prebuild checks, and validates the Proton payload needed by the current Linux-only repo. Linux builds do not commit a pregenerated zip; `./build.sh --prod` refreshes `BepInExSource/linux/BepInEx.zip` from the installer's Proton payload source directory before building the local app binary.

## Derivative Work Notice

If you plan to build on top of this project or release derivative mods, make sure your work complies with *The Bazaar* official Mod Policy:

[The Bazaar Mod Policy](https://www.playthebazaar.com/mod-policy)

## Acknowledgements

- **Original Project**: [BazaarPlusPlus](https://github.com/cauyxy/BazaarPlusPlus)
- **Inspiration**: [BazaarHelper](https://github.com/Duangi/BazaarHelper), [BazaarPlannerMod](https://github.com/oceanseth/BazaarPlannerMod)
- **Data reference**: [bazaardb.gg](https://bazaardb.gg)
- **Runtime dependencies**: [BepInEx](https://github.com/BepInEx/BepInEx), [Harmony](https://github.com/pardeike/Harmony), [Tauri](https://tauri.app), [React](https://react.dev), [Vite](https://vite.dev), [Tailwind CSS](https://tailwindcss.com), [FFmpeg](https://ffmpeg.org)
- **Font**: [LXGW WenKai](https://github.com/lxgw/LxgwWenKai) (SIL Open Font License 1.1)
- **Co-creators**: [Codex](https://openai.com/codex), [Claude Code](https://claude.com/product/claude-code)

## License

Released under the [MIT License](LICENSE).
