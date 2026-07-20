#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# Some VPN/tunnel configurations advertise an unusable IPv6 route. Keep builds on
# the working IPv4 path by default while allowing callers to opt back into IPv6.
export DOTNET_SYSTEM_NET_DISABLEIPV6="${DOTNET_SYSTEM_NET_DISABLEIPV6:-1}"

case "$(uname -s)" in
    Linux)
        PLATFORM="Linux (Proton)"
        GAME_ROOT=""
        MANAGED=""
        ;;
    *)
        echo -e "${RED}This repository only supports Linux/Proton. Current platform: $(uname -s)${RESET}" >&2
        exit 1
        ;;
esac

echo -e "${CYAN}== Building on ${GREEN}${PLATFORM}${CYAN} ==${RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="${BPP_GAME_ROOT:-$GAME_ROOT}"
MANAGED="${BPP_MANAGED_PATH:-$MANAGED}"
INSTALLER_SOURCE="${BPP_INSTALLER_SOURCE_PATH:-$SCRIPT_DIR/../bazaarplusplus-installer/src-tauri/resources}"
PROTON_PAYLOAD="$INSTALLER_SOURCE/SourceForBuild/proton"
PROTON_FFMPEG_ZIP="$INSTALLER_SOURCE/FfmpegSource/proton/ffmpeg.zip"
PROTON_FFMPEG_LICENSE="$INSTALLER_SOURCE/FfmpegSource/proton/LICENSE.txt"
MAIN_PROJECT="$SCRIPT_DIR/src/BazaarPlusPlus/BazaarPlusPlus.csproj"
AGENT_HOST_PROJECT="$SCRIPT_DIR/src/BazaarPlusPlus.BazaarAgentHost/BazaarPlusPlus.BazaarAgentHost.csproj"
RELEASE_OUTPUT_DIR="${BPP_RELEASE_OUTPUT_PATH:-$SCRIPT_DIR/src/BazaarPlusPlus/bin/Release/netstandard2.1}"
AGENT_RELEASE_OUTPUT_DIR="${BPP_AGENT_RELEASE_OUTPUT_PATH:-$SCRIPT_DIR/src/BazaarPlusPlus.BazaarAgentHost/bin/Release/netstandard2.1}"
PROTON_STEAM_LAUNCH_OPTIONS='WINEDLLOVERRIDES="winhttp=n,b" %command%'

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

has_proton_payload() {
    [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.dll" ]] &&
        [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.version" ]] &&
        [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.ModApi.dll" ]] &&
        [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.Localization.dll" ]] &&
        [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.Storage.dll" ]] &&
        [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.BazaarAgent.dll" ]] &&
        [[ -f "$PROTON_PAYLOAD/BepInEx/plugins/BazaarPlusPlus.BazaarAgentHost.dll" ]]
}

has_release_overlay() {
    [[ -f "$RELEASE_OUTPUT_DIR/BazaarPlusPlus.dll" ]] &&
        [[ -f "$RELEASE_OUTPUT_DIR/BazaarPlusPlus.version" ]] &&
        [[ -f "$RELEASE_OUTPUT_DIR/BazaarPlusPlus.ModApi.dll" ]] &&
        [[ -f "$RELEASE_OUTPUT_DIR/BazaarPlusPlus.Localization.dll" ]] &&
        [[ -f "$RELEASE_OUTPUT_DIR/BazaarPlusPlus.Storage.dll" ]] &&
        [[ -f "$AGENT_RELEASE_OUTPUT_DIR/BazaarPlusPlus.BazaarAgent.dll" ]] &&
        [[ -f "$AGENT_RELEASE_OUTPUT_DIR/BazaarPlusPlus.BazaarAgentHost.dll" ]]
}

build_proton_payload_for_game() {
    local managed="$1"
    local game_root="$2"

    dotnet build "$AGENT_HOST_PROJECT" \
        -c Release \
        -p:ManagedPath="$managed" \
        -p:GamePath="$game_root" \
        -p:BuildProductionPackage=true \
        -verbosity minimal
}

copy_release_overlay_into_game_root() {
    local game_root="$1"
    local plugins_dir="$game_root/BepInEx/plugins"
    local required=(
        BazaarPlusPlus.dll
        BazaarPlusPlus.version
        BazaarPlusPlus.ModApi.dll
        BazaarPlusPlus.Localization.dll
        BazaarPlusPlus.Storage.dll
    )
    local required_agent=(
        BazaarPlusPlus.BazaarAgent.dll
        BazaarPlusPlus.BazaarAgentHost.dll
    )
    local name

    mkdir -p "$plugins_dir"
    for name in "${required[@]}"; do
        assert_file "$RELEASE_OUTPUT_DIR/$name" "release artifact $name"
        cp "$RELEASE_OUTPUT_DIR/$name" "$plugins_dir/$name"
    done

    for name in "${required_agent[@]}"; do
        assert_file "$AGENT_RELEASE_OUTPUT_DIR/$name" "release artifact $name"
        cp "$AGENT_RELEASE_OUTPUT_DIR/$name" "$plugins_dir/$name"
    done
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

    assert_command cp

    game_root="$(resolve_proton_game_root "$explicit_game_root")"
    managed="$game_root/TheBazaar_Data/Managed"

    if [[ "$skip_build" == false ]]; then
        if command -v dotnet &>/dev/null; then
            echo -e "${CYAN}== Building Release mod for Proton game assemblies ==${RESET}"
            build_proton_payload_for_game "$managed" "$game_root"
        elif has_proton_payload || has_release_overlay; then
            echo -e "${CYAN}== dotnet not found; reusing existing Release artifacts ==${RESET}"
        else
            echo -e "${RED}Missing command: dotnet. Install .NET SDK 8 or newer, or provide prebuilt Release artifacts.${RESET}" >&2
            exit 1
        fi
    fi

    if ! has_proton_payload && ! has_release_overlay; then
        echo -e "${RED}Missing complete built payload: neither $PROTON_PAYLOAD nor the Release output directories contain every required plugin artifact.${RESET}" >&2
        echo "Build the mod once, or place prebuilt Release artifacts under:" >&2
        echo "  $RELEASE_OUTPUT_DIR" >&2
        echo "  $AGENT_RELEASE_OUTPUT_DIR" >&2
        exit 1
    fi

    echo -e "${CYAN}== Copying Proton BepInEx payload ==${RESET}"
    cp -R "$PROTON_PAYLOAD"/. "$game_root"/

    if ! has_proton_payload; then
        echo -e "${CYAN}== Overlaying existing Release artifacts ==${RESET}"
        copy_release_overlay_into_game_root "$game_root"
    fi

    if [[ "$skip_ffmpeg" == false && -f "$PROTON_FFMPEG_ZIP" ]]; then
        assert_command unzip "Install unzip, or rerun with --skip-ffmpeg."
        echo -e "${CYAN}== Installing bundled Proton ffmpeg ==${RESET}"
        mkdir -p "$game_root/BepInEx/plugins"
        unzip -oq "$PROTON_FFMPEG_ZIP" -d "$game_root/BepInEx/plugins"
        if [[ -f "$PROTON_FFMPEG_LICENSE" ]]; then
            cp "$PROTON_FFMPEG_LICENSE" "$game_root/BepInEx/plugins/ffmpeg-LICENSE.txt"
        fi
    fi

    print_proton_result "$game_root"
}

build_payload() {
    local explicit_game_root=""
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
            *)
                usage
                exit 1
                ;;
        esac
    done

    assert_command dotnet "Install .NET SDK 8 or newer."
    game_root="$(resolve_proton_game_root "$explicit_game_root")"
    managed="$game_root/TheBazaar_Data/Managed"

    echo -e "${CYAN}== Building Linux/Proton installer payload ==${RESET}"
    build_proton_payload_for_game "$managed" "$game_root"
    echo -e "${GREEN}Proton payload refreshed:${RESET}"
    echo "  $PROTON_PAYLOAD"
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
    local fast="${1:-false}"
    local args=(-c Release)

    if [[ "$fast" == "true" ]]; then
        args+=(--no-restore)
    fi

    dotnet build "$MAIN_PROJECT" ${args[@]+"${args[@]}"}
}

format() {
    dotnet tool restore
    dotnet csharpier format .
}

format_check() {
    dotnet tool restore
    dotnet csharpier check .
}

usage() {
    cat <<EOF
Usage:
  $0 build [--fast]
  $0 build-payload [--game-dir PATH]
  $0 install [--game-dir PATH] [--skip-build] [--skip-ffmpeg]
  $0 proton-install [--game-dir PATH] [--skip-build] [--skip-ffmpeg]
  $0 proton-log [--game-dir PATH] [--lines N]
  $0 format
  $0 format-check

Options:
  --fast              With build: skip NuGet restore (rerun without it after csproj edits or in a fresh worktree).
  --game-dir PATH     Proton game root containing TheBazaar.exe (auto-detected on Linux when omitted).
  --skip-build        With install: copy the existing Proton payload only.
  --skip-ffmpeg       With install: do not install bundled Proton ffmpeg.

Environment:
  BPP_RELEASE_OUTPUT_PATH        Override the main plugin Release artifact directory used when dotnet is unavailable.
  BPP_AGENT_RELEASE_OUTPUT_PATH  Override the BazaarAgent host Release artifact directory used when dotnet is unavailable.
EOF
}

case "${1:-}" in
    build)
        shift
        fast=false
        while (($# > 0)); do
            case "$1" in
                --fast) fast=true ;;
                *)
                    usage
                    exit 1
                    ;;
            esac
            shift
        done
        build "$fast"
        ;;
    build-payload)
        shift
        build_payload "$@"
        ;;
    format)       format ;;
    format-check) format_check ;;
    install)
        shift
        proton_install "$@"
        ;;
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
