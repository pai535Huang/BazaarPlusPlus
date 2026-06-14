#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

case "$(uname -s)" in
    Darwin)
        PLATFORM="macOS"
        GAME_ROOT="$HOME/Library/Application Support/Steam/steamapps/common/The Bazaar"
        MANAGED="$HOME/Library/Application Support/Steam/steamapps/common/The Bazaar/TheBazaar.app/Contents/Resources/Data/Managed"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="Windows (Git Bash)"
        GAME_ROOT="/c/Program Files (x86)/Steam/steamapps/common/The Bazaar"
        MANAGED="/c/Program Files (x86)/Steam/steamapps/common/The Bazaar/TheBazaar_Data/Managed"
        ;;
    Linux)
        PLATFORM="Linux (Proton)"
        GAME_ROOT=""
        MANAGED=""
        ;;
    *)
        echo -e "${RED}Unsupported platform: $(uname -s)${RESET}" >&2
        exit 1
        ;;
esac

echo -e "${CYAN}== Platform: ${GREEN}${PLATFORM}${CYAN} ==${RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_SQLITE="$SCRIPT_DIR/../bazaarplusplus-installer/src-tauri/resources/SourceForBuild/macos/BepInEx/plugins/libe_sqlite3.dylib"
GAME_SQLITE="$GAME_ROOT/BepInEx/plugins/libe_sqlite3.dylib"
WINDOWS_PAYLOAD="$SCRIPT_DIR/../bazaarplusplus-installer/src-tauri/resources/SourceForBuild/windows"
WINDOWS_FFMPEG_ZIP="$SCRIPT_DIR/../bazaarplusplus-installer/src-tauri/resources/FfmpegSource/windows/ffmpeg.zip"
WINDOWS_FFMPEG_LICENSE="$SCRIPT_DIR/../bazaarplusplus-installer/src-tauri/resources/FfmpegSource/windows/LICENSE.txt"
PROTON_STEAM_LAUNCH_OPTIONS='WINEDLLOVERRIDES="winhttp=n,b" %command%'

clear_macos_sqlite_quarantine() {
    [[ "$PLATFORM" == "macOS" ]] || return 0

    local target
    for target in "$INSTALLER_SQLITE" "$GAME_SQLITE"; do
        [[ -f "$target" ]] || continue
        xattr -d com.apple.quarantine "$target" 2>/dev/null || true
    done
}

require_non_linux_build_platform() {
    if [[ "$PLATFORM" == "Linux (Proton)" ]]; then
        echo -e "${RED}Use '$0 proton-install' for Linux/Proton testing.${RESET}" >&2
        exit 1
    fi
}

assert_command() {
    local name="$1"
    local hint="${2:-}"

    if ! command -v "$name" &>/dev/null; then
        if [[ -n "$hint" ]]; then
            echo -e "${RED}Missing command: $name. $hint${RESET}" >&2
        else
            echo -e "${RED}Missing command: $name.${RESET}" >&2
        fi
        exit 1
    fi
}

is_proton_game_root() {
    local path="$1"

    [[ -f "$path/TheBazaar.exe" && -f "$path/TheBazaar_Data/Managed/Assembly-CSharp.dll" ]]
}

canonical_path() {
    local path="$1"

    if command -v readlink &>/dev/null; then
        readlink -f "$path" 2>/dev/null || printf '%s\n' "$path"
    else
        printf '%s\n' "$path"
    fi
}

steam_library_vdf_files() {
    local candidate
    for candidate in \
        "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
        "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"; do
        [[ -f "$candidate" ]] && printf '%s\n' "$candidate"
    done
}

steam_library_paths() {
    local vdf
    while IFS= read -r vdf; do
        sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)".*/\1/p' "$vdf"
    done < <(steam_library_vdf_files)
}

proton_game_candidates() {
    local candidate
    local library

    for candidate in \
        "$HOME/.local/share/Steam/steamapps/common/The Bazaar" \
        "$HOME/.steam/steam/steamapps/common/The Bazaar" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/The Bazaar"; do
        is_proton_game_root "$candidate" && printf '%s\n' "$candidate"
    done

    while IFS= read -r library; do
        [[ -n "$library" ]] || continue
        candidate="$library/steamapps/common/The Bazaar"
        is_proton_game_root "$candidate" && printf '%s\n' "$candidate"
    done < <(steam_library_paths)
}

resolve_proton_game_root() {
    local explicit_game_root="$1"
    local candidates=()

    if [[ -n "$explicit_game_root" ]]; then
        if ! is_proton_game_root "$explicit_game_root"; then
            echo -e "${RED}Invalid Proton game directory: $explicit_game_root${RESET}" >&2
            echo "Expected TheBazaar.exe and TheBazaar_Data/Managed/Assembly-CSharp.dll under it." >&2
            exit 1
        fi
        printf '%s\n' "$explicit_game_root"
        return
    fi

    if [[ -n "${BPP_PROTON_GAME_DIR:-}" ]]; then
        resolve_proton_game_root "$BPP_PROTON_GAME_DIR"
        return
    fi

    mapfile -t candidates < <(
        while IFS= read -r candidate; do
            canonical_path "$candidate"
        done < <(proton_game_candidates) | awk '!seen[$0]++'
    )

    case "${#candidates[@]}" in
        0)
            echo -e "${RED}Could not find a Proton install of The Bazaar.${RESET}" >&2
            echo "Pass it explicitly: $0 proton-install --game-dir '/path/to/steamapps/common/The Bazaar'" >&2
            exit 1
            ;;
        1)
            printf '%s\n' "${candidates[0]}"
            ;;
        *)
            echo -e "${RED}Found multiple The Bazaar installs. Pass one with --game-dir:${RESET}" >&2
            printf '  %s\n' "${candidates[@]}" >&2
            exit 1
            ;;
    esac
}

print_proton_result() {
    local game_root="$1"

    echo -e "${GREEN}Proton payload installed.${RESET}"
    echo "Game directory:"
    echo "  $game_root"
    echo
    echo "Set this Steam launch option for The Bazaar:"
    echo "  $PROTON_STEAM_LAUNCH_OPTIONS"
    echo
    echo "After launching the game, inspect:"
    echo "  $game_root/BepInEx/LogOutput.log"
    echo
    echo "Quick check:"
    echo "  $0 proton-log --game-dir '$game_root'"
}

proton_install() {
    local explicit_game_root=""
    local skip_build=false
    local skip_ffmpeg=false
    local game_root
    local managed

    while (($# > 0)); do
        case "$1" in
            --game-dir)
                explicit_game_root="${2:-}"
                if [[ -z "$explicit_game_root" ]]; then
                    echo -e "${RED}--game-dir requires a path.${RESET}" >&2
                    exit 1
                fi
                shift 2
                ;;
            --skip-build)
                skip_build=true
                shift
                ;;
            --skip-ffmpeg)
                skip_ffmpeg=true
                shift
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    assert_command dotnet "Install .NET SDK 8 or newer."
    assert_command cp

    game_root="$(resolve_proton_game_root "$explicit_game_root")"
    managed="$game_root/TheBazaar_Data/Managed"

    if [[ "$skip_build" == false ]]; then
        echo -e "${CYAN}== Building Release mod for Proton game assemblies ==${RESET}"
        dotnet build "$SCRIPT_DIR/src/BazaarPlusPlus/BazaarPlusPlus.csproj" \
            -c Release \
            -p:ManagedPath="$managed" \
            -p:GamePath="$game_root" \
            -verbosity minimal
    fi

    if [[ ! -f "$WINDOWS_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.dll" ]]; then
        echo -e "${RED}Missing built plugin: $WINDOWS_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.dll${RESET}" >&2
        echo "Run without --skip-build, or fix the build errors above." >&2
        exit 1
    fi

    echo -e "${CYAN}== Copying Windows BepInEx payload ==${RESET}"
    cp -R "$WINDOWS_PAYLOAD"/. "$game_root"/

    if [[ "$skip_ffmpeg" == false && -f "$WINDOWS_FFMPEG_ZIP" ]]; then
        assert_command unzip "Install unzip, or rerun with --skip-ffmpeg."
        echo -e "${CYAN}== Installing bundled Windows ffmpeg ==${RESET}"
        mkdir -p "$game_root/BepInEx/plugins"
        unzip -oq "$WINDOWS_FFMPEG_ZIP" -d "$game_root/BepInEx/plugins"
        if [[ -f "$WINDOWS_FFMPEG_LICENSE" ]]; then
            cp "$WINDOWS_FFMPEG_LICENSE" "$game_root/BepInEx/plugins/ffmpeg-LICENSE.txt"
        fi
    fi

    print_proton_result "$game_root"
}

proton_log() {
    local explicit_game_root=""
    local lines=120
    local game_root
    local log_path

    while (($# > 0)); do
        case "$1" in
            --game-dir)
                explicit_game_root="${2:-}"
                if [[ -z "$explicit_game_root" ]]; then
                    echo -e "${RED}--game-dir requires a path.${RESET}" >&2
                    exit 1
                fi
                shift 2
                ;;
            --lines)
                lines="${2:-}"
                if [[ -z "$lines" ]]; then
                    echo -e "${RED}--lines requires a number.${RESET}" >&2
                    exit 1
                fi
                shift 2
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    game_root="$(resolve_proton_game_root "$explicit_game_root")"
    log_path="$game_root/BepInEx/LogOutput.log"

    if [[ ! -f "$log_path" ]]; then
        echo -e "${RED}BepInEx log not found: $log_path${RESET}" >&2
        echo "Start the game through Steam with:" >&2
        echo "  $PROTON_STEAM_LAUNCH_OPTIONS" >&2
        exit 1
    fi

    tail -n "$lines" "$log_path"
}

build() {
    require_non_linux_build_platform
    local args=(-verbosity detailed)

    dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj "${args[@]}"
}

build_all() {
    require_non_linux_build_platform
    local prod="${1:-false}"
    local args=(-t:BuildAll -verbosity detailed)

    if [[ "$prod" == "true" ]]; then
        args+=(-p:BuildProductionPackage=true)
    fi

    clear_macos_sqlite_quarantine
    dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj "${args[@]}"
    clear_macos_sqlite_quarantine
}

parse_build_options() {
    if (($# > 0)); then
        usage
        exit 1
    fi

    build
}

test_all() {
    require_non_linux_build_platform
    clear_macos_sqlite_quarantine

    local project
    local failures=()
    while IFS= read -r project; do
        echo -e "${CYAN}== Testing ${GREEN}${project}${CYAN} ==${RESET}"
        if grep -q "Microsoft.NET.Test.Sdk" "$project"; then
            if ! dotnet test "$project"; then
                failures+=("$project")
            fi
        else
            if ! dotnet run --project "$project"; then
                failures+=("$project")
            fi
        fi
    done < <(find tests -mindepth 2 -maxdepth 2 -name '*.csproj' | sort)

    clear_macos_sqlite_quarantine

    if ((${#failures[@]} > 0)); then
        echo -e "${RED}Failed test projects:${RESET}" >&2
        printf '  %s\n' "${failures[@]}" >&2
        return 1
    fi
}

format() {
    csharpier format .
}

check_ilspy() {
    if ! command -v ilspycmd &>/dev/null; then
        echo "ilspycmd not found. Installing..."
        dotnet tool install -g ilspycmd
    fi
}

decompile() {
    require_non_linux_build_platform
    check_ilspy
    local dll="${2:-Assembly-CSharp}"
    local out="./decompiled/$dll"
    echo "Decompiling $dll to $out..."
    DOTNET_ROLL_FORWARD=Major ilspycmd -p -o "$out" "$MANAGED/$dll.dll"
    echo "Done: $out"
}

decompile_all() {
    for dll in Assembly-CSharp BazaarGameClient BazaarGameShared BazaarBattleService TheBazaarRuntime FMODUnity; do
        decompile _ "$dll"
    done
}

usage() {
    cat <<EOF
Usage:
  $0 build
  $0 all [--prod]
  $0 test
  $0 format
  $0 decompile [DllName]
  $0 decompile-all
  $0 proton-install [--game-dir PATH] [--skip-build] [--skip-ffmpeg]
  $0 proton-log [--game-dir PATH] [--lines N]

Options:
  --prod              With all: also build the production installer package.
  --game-dir PATH     Proton game root containing TheBazaar.exe.
  --skip-build        With proton-install: copy the existing Windows payload only.
  --skip-ffmpeg       With proton-install: do not install bundled Windows ffmpeg.
EOF
}

case "${1:-}" in
    all)
        shift
        prod=false
        while (($# > 0)); do
            case "$1" in
                --prod) prod=true ;;
                *)
                    usage
                    exit 1
                    ;;
            esac
            shift
        done
        build_all "$prod"
        ;;
    build)
        shift
        parse_build_options "$@"
        ;;
    test)       test_all ;;
    format)     format ;;
    decompile)  decompile "$@" ;;
    decompile-all) decompile_all ;;
    proton-install)
        shift
        proton_install "$@"
        ;;
    proton-log)
        shift
        proton_log "$@"
        ;;
    *)
        usage
        exit 1
        ;;
esac
