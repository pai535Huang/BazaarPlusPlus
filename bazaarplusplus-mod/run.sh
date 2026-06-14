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

echo -e "${CYAN}== Building on ${GREEN}${PLATFORM}${CYAN} ==${RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="${BPP_GAME_ROOT:-$GAME_ROOT}"
MANAGED="${BPP_MANAGED_PATH:-$MANAGED}"
INSTALLER_SOURCE="${BPP_INSTALLER_SOURCE_PATH:-$SCRIPT_DIR/../bazaarplusplus-installer/src-tauri/resources}"
GAME_SQLITE="$GAME_ROOT/BepInEx/plugins/libe_sqlite3.dylib"
WINDOWS_PAYLOAD="$INSTALLER_SOURCE/SourceForBuild/windows"
WINDOWS_FFMPEG_ZIP="$INSTALLER_SOURCE/FfmpegSource/windows/ffmpeg.zip"
WINDOWS_FFMPEG_LICENSE="$INSTALLER_SOURCE/FfmpegSource/windows/LICENSE.txt"
PROTON_STEAM_LAUNCH_OPTIONS='WINEDLLOVERRIDES="winhttp=n,b" %command%'
TRAMPOLINE_REPAIR_SCRIPT="$SCRIPT_DIR/scripts/repair-macos-trampoline.sh"
PUBLISHED_PROJECTS=(
    src/BazaarPlusPlus.Localization/BazaarPlusPlus.Localization.csproj
    src/BazaarPlusPlus.ModApi/BazaarPlusPlus.ModApi.csproj
    src/BazaarPlusPlus.Storage/BazaarPlusPlus.Storage.csproj
    src/BazaarPlusPlus/BazaarPlusPlus.csproj
    src/BazaarPlusPlus.BazaarAgent/BazaarPlusPlus.BazaarAgent.csproj
    src/BazaarPlusPlus.BazaarAgentHost/BazaarPlusPlus.BazaarAgentHost.csproj
)

clear_macos_sqlite_quarantine() {
    [[ "$PLATFORM" == "macOS" ]] || return 0

    local installer_source="${1:-$INSTALLER_SOURCE}"
    local target
    for target in "$installer_source/SourceForBuild/macos/BepInEx/plugins/libe_sqlite3.dylib" "$GAME_SQLITE"; do
        [[ -f "$target" ]] || continue
        xattr -d com.apple.quarantine "$target" 2>/dev/null || true
    done
}

print_bazaaragent_mode() {
    local bazaaragent="${1:-false}"
    if [[ "$bazaaragent" == "true" ]]; then
        echo -e "${CYAN}== BazaarAgent: ${GREEN}included${CYAN} ==${RESET}"
    else
        echo -e "${CYAN}== BazaarAgent: excluded ==${RESET}"
    fi
}

repair_macos_trampoline() {
    [[ "$PLATFORM" == "macOS" ]] || return 0

    local installer_source="${1:-$INSTALLER_SOURCE}"
    local trampoline_stub="${BPP_TRAMPOLINE_STUB:-$installer_source/Trampoline/macos/bpp_launcher}"
    BPP_GAME_ROOT="$GAME_ROOT" \
        BPP_TRAMPOLINE_STUB="$trampoline_stub" \
        bash "$TRAMPOLINE_REPAIR_SCRIPT"
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
            -p:BuildProductionPackage=true \
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
    local bazaaragent="${1:-false}"
    local fast="${2:-false}"
    local args=()

    if [[ "$fast" == "true" ]]; then
        # Inner-loop accelerator: skips NuGet restore. Run a normal build after
        # editing any csproj or creating a fresh worktree.
        args+=(--no-restore)
    fi

    print_bazaaragent_mode "$bazaaragent"
    repair_macos_trampoline
    # The host is its own plugin project that references the main plugin + the pure core,
    # so building it builds and deploys all three. A default build builds only the main
    # plugin, whose build actively scrubs both host dlls from the plugins folder.
    if [[ "$bazaaragent" == "true" ]]; then
        dotnet build src/BazaarPlusPlus.BazaarAgentHost/BazaarPlusPlus.BazaarAgentHost.csproj ${args[@]+"${args[@]}"}
    else
        dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj ${args[@]+"${args[@]}"}
    fi
}

# Production publishing copies the DLL into the installer resources that ship to
# ONLINE users, but online/PTR share one install directory — a publish run while the
# PTR branch is installed would ship a PTR-assembly build. Pin production builds to
# an online Managed snapshot (game-libs/online-*/Managed, newest) when one exists;
# otherwise require the installed branch to actually be public.
resolve_release_managed() {
    local pinned="${BPP_RELEASE_MANAGED:-}"
    if [[ -n "$pinned" ]]; then
        echo "$pinned"
        return
    fi
    local snaps=("$SCRIPT_DIR"/game-libs/online-*/Managed)
    local last=""
    local snap
    for snap in "${snaps[@]}"; do
        [[ -d "$snap" ]] && last="$snap"
    done
    echo "$last"
}

resolve_installer_source() {
    local resolved="$INSTALLER_SOURCE"
    local arg
    for arg in "$@"; do
        case "$arg" in
            -p:BPPInstallerSourcePath=*|--property:BPPInstallerSourcePath=*)
                resolved="${arg#*=}"
                ;;
        esac
    done
    echo "$resolved"
}

fetch_remote_data() {
    local args=("$@")
    dotnet msbuild src/BazaarPlusPlus/BazaarPlusPlus.csproj \
        -t:FetchRemoteEmbeddedData \
        ${args[@]+"${args[@]}"} \
        -p:ForceRemoteEmbeddedDataRefresh=true
}

run_seed_gates() {
    local args=("$@")
    echo -e "${CYAN}== Validating ${GREEN}voice subtitle embedded seed${CYAN} ==${RESET}"
    dotnet test tests/VoiceSubtitles.Tests/VoiceSubtitles.Tests.csproj \
        -c Release \
        ${args[@]+"${args[@]}"}
    echo -e "${CYAN}== Validating ${GREEN}live build recommendation embedded seed${CYAN} ==${RESET}"
    dotnet run --project tests/LiveBuildRecommendations.Tests/LiveBuildRecommendations.Tests.csproj \
        -c Release \
        ${args[@]+"${args[@]}"}
}

publish() {
    local bazaaragent="${1:-false}"
    shift || true
    local passthrough_args=("$@")
    local installer_source
    installer_source=$(resolve_installer_source ${passthrough_args[@]+"${passthrough_args[@]}"})
    if [[ ! -d "$installer_source" ]]; then
        echo -e "${RED}Installer resources not found at '$installer_source'.${RESET}" >&2
        echo -e "${RED}Pass -p:BPPInstallerSourcePath=/absolute/path/to/resources.${RESET}" >&2
        exit 1
    fi

    local common_args=(
        ${passthrough_args[@]+"${passthrough_args[@]}"}
        "-p:BPPInstallerSourcePath=$installer_source"
    )

    local release_managed=""
    release_managed=$(resolve_release_managed)
    if [[ -n "$release_managed" ]]; then
        echo -e "${CYAN}== Release pinned to ${GREEN}${release_managed}${CYAN} ==${RESET}"
        common_args+=("-p:ManagedPath=$release_managed")
    else
        require_steam_branch public
    fi

    print_bazaaragent_mode "$bazaaragent"
    clear_macos_sqlite_quarantine "$installer_source"
    repair_macos_trampoline "$installer_source"

    fetch_remote_data "${common_args[@]}"
    run_seed_gates "${common_args[@]}" -p:RemoteEmbeddedDataPrepared=true

    local build_args=(
        -t:BuildAll
        "${common_args[@]}"
        -p:BuildProductionPackage=true
        -p:RemoteEmbeddedDataPrepared=true
    )
    if [[ "$bazaaragent" == "true" ]]; then
        dotnet build src/BazaarPlusPlus.BazaarAgentHost/BazaarPlusPlus.BazaarAgentHost.csproj "${build_args[@]}"
    else
        dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj "${build_args[@]}"
    fi
    clear_macos_sqlite_quarantine "$installer_source"
}

parse_build_options() {
    local bazaaragent=false
    local fast=false

    while (($# > 0)); do
        case "$1" in
            --with-bazaaragent) bazaaragent=true ;;
            --fast) fast=true ;;
            *)
                usage
                exit 1
                ;;
        esac
        shift
    done

    build "$bazaaragent" "$fast"
}

parse_publish_options() {
    local bazaaragent=false
    local msbuild_args=()

    while (($# > 0)); do
        case "$1" in
            --with-bazaaragent) bazaaragent=true ;;
            -p:*|--property:*) msbuild_args+=("$1") ;;
            *)
                usage
                exit 1
                ;;
        esac
        shift
    done

    publish "$bazaaragent" ${msbuild_args[@]+"${msbuild_args[@]}"}
}

parse_fetch_data_options() {
    local msbuild_args=()

    while (($# > 0)); do
        case "$1" in
            -p:*|--property:*) msbuild_args+=("$1") ;;
            *)
                usage
                exit 1
                ;;
        esac
        shift
    done

    fetch_remote_data ${msbuild_args[@]+"${msbuild_args[@]}"}
}

test_all() {
    [[ "$PLATFORM" == "Linux (Proton)" ]] && {
        echo -e "${RED}Use '$0 proton-install' for Linux/Proton validation.${RESET}" >&2
        exit 1
    }

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

restore_locks() {
    local project
    for project in "${PUBLISHED_PROJECTS[@]}"; do
        echo -e "${CYAN}== Refreshing NuGet lock for ${GREEN}${project}${CYAN} ==${RESET}"
        dotnet restore "$project" --force-evaluate
    done
}

restore_locked() {
    local project
    for project in "${PUBLISHED_PROJECTS[@]}"; do
        echo -e "${CYAN}== Validating NuGet lock for ${GREEN}${project}${CYAN} ==${RESET}"
        dotnet restore "$project" --locked-mode
    done
}

restore_dotnet_tools() {
    dotnet tool restore
}

format() {
    restore_dotnet_tools
    dotnet csharpier format .
}

format_check() {
    restore_dotnet_tools
    dotnet csharpier check .
}

check_ilspy() {
    if ! command -v ilspycmd &>/dev/null; then
        echo "ilspycmd not found. Installing..."
        dotnet tool install -g ilspycmd
    fi
}

# Steam beta branches ("public_test_realm" = PTR) replace the single install
# in place, so the Managed dir silently changes identity on branch switch.
# Guard so PTR bits never overwrite ./decompiled (online reference) and vice versa.
# The appmanifest is located by walking up from MANAGED — the directory the DLLs
# are actually read from — so an overridden BPP_MANAGED_PATH is guarded too.
locate_appmanifest() {
    local dir="$MANAGED"
    local _i
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        dir="$(dirname "$dir")"
        if [[ -f "$dir/appmanifest_1617400.acf" ]]; then
            echo "$dir/appmanifest_1617400.acf"
            return
        fi
        [[ "$dir" == "/" || "$dir" == "." ]] && break
    done
}

installed_steam_branch() {
    local acf
    acf=$(locate_appmanifest)
    [[ -n "$acf" ]] || { echo "unknown"; return; }
    local key
    key=$(awk '/"MountedConfig"/,/^\t\}/' "$acf" | awk -F '"' '/"BetaKey"/ {print $4}')
    echo "${key:-public}"
}

require_steam_branch() {
    local expected="$1"
    [[ "${BPP_SKIP_BRANCH_CHECK:-}" == "1" ]] && return 0
    local branch
    branch=$(installed_steam_branch)
    if [[ "$branch" == "unknown" ]]; then
        echo -e "${RED}Could not find appmanifest_1617400.acf above the Managed path to verify the Steam branch.${RESET}" >&2
        echo -e "${RED}Decompiling a bare copied Managed dir? Set BPP_SKIP_BRANCH_CHECK=1 to override.${RESET}" >&2
        exit 1
    fi
    if [[ "$branch" != "$expected" ]]; then
        echo -e "${RED}Installed Steam branch is '$branch', expected '$expected'.${RESET}" >&2
        echo -e "${RED}Switch The Bazaar's beta branch in Steam first, or set BPP_SKIP_BRANCH_CHECK=1 to override.${RESET}" >&2
        exit 1
    fi
}

decompile() {
    [[ "$PLATFORM" == "Linux (Proton)" ]] && {
        echo -e "${RED}Decompile commands require a native macOS or Windows install.${RESET}" >&2
        exit 1
    }

    check_ilspy
    local dll="${2:-Assembly-CSharp}"
    local out_root="${BPP_DECOMPILE_OUT:-./decompiled}"
    local out="$out_root/$dll"
    echo "Decompiling $dll to $out..."
    DOTNET_ROLL_FORWARD=Major ilspycmd -p -o "$out" "$MANAGED/$dll.dll"
    echo "Done: $out"
}

decompile_all() {
    for dll in Assembly-CSharp BazaarGameClient BazaarGameShared BazaarBattleService TheBazaarRuntime FMODUnity; do
        decompile _ "$dll"
    done
}

# Archive the currently installed Managed dir keyed by branch + buildid. Because the
# two branches overwrite each other in place, this is the only way to keep both
# assembly sets available (Release pinning + build-matrix consume these snapshots).
snapshot_managed() {
    local acf branch buildid channel dest
    acf=$(locate_appmanifest)
    if [[ -z "$acf" ]]; then
        echo -e "${RED}Could not find appmanifest_1617400.acf above the Managed path.${RESET}" >&2
        exit 1
    fi
    branch=$(installed_steam_branch)
    channel="online"
    [[ "$branch" == "public_test_realm" ]] && channel="ptr"
    if [[ "$branch" != "public" && "$branch" != "public_test_realm" ]]; then
        echo -e "${RED}Installed branch '$branch' is neither public nor public_test_realm; refusing to snapshot.${RESET}" >&2
        exit 1
    fi
    buildid=$(awk -F '"' '/"buildid"/ {print $4; exit}' "$acf")
    dest="$SCRIPT_DIR/game-libs/$channel-$buildid/Managed"
    if [[ -d "$dest" ]]; then
        echo "Snapshot already exists: $dest"
        return
    fi
    mkdir -p "$dest"
    cp -R "$MANAGED/." "$dest/"
    echo -e "${GREEN}Archived $channel (buildid $buildid) Managed -> $dest${RESET}"
}

# Compile the single source tree against every archived Managed snapshot. Uses the
# CompatCheck configuration so neither the Debug plugins-copy nor the Release
# installer-copy post-build steps fire.
build_matrix() {
    local snaps=("$SCRIPT_DIR"/game-libs/*/Managed)
    local found=0 failed=()
    local snap
    for snap in "${snaps[@]}"; do
        [[ -d "$snap" ]] || continue
        found=1
        echo -e "${CYAN}== Matrix build against ${GREEN}${snap}${CYAN} ==${RESET}"
        if ! dotnet build src/BazaarPlusPlus/BazaarPlusPlus.csproj -c CompatCheck -p:ManagedPath="$snap"; then
            failed+=("$snap")
        fi
    done
    if ((found == 0)); then
        echo -e "${RED}No snapshots under game-libs/. Run './run.sh snapshot-managed' on each branch first.${RESET}" >&2
        exit 1
    fi
    if ((${#failed[@]} > 0)); then
        echo -e "${RED}Matrix build failed against:${RESET}" >&2
        printf '  %s\n' "${failed[@]}" >&2
        exit 1
    fi
    echo -e "${GREEN}Matrix build passed for all snapshots.${RESET}"
}

usage() {
    cat <<EOF
Usage:
  $0 build [--with-bazaaragent] [--fast]
  $0 publish [--with-bazaaragent] [-p:Name=Value ...]
  $0 fetch-data [-p:Name=Value ...]
  $0 restore-locks
  $0 restore-locked
  $0 test
  $0 format
  $0 format-check
  $0 decompile [DllName]
  $0 decompile-all
  $0 decompile-ptr [DllName]
  $0 decompile-all-ptr
  $0 snapshot-managed
  $0 build-matrix
  $0 proton-install [--game-dir PATH] [--skip-build] [--skip-ffmpeg]
  $0 proton-log [--game-dir PATH] [--lines N]

Options:
  --with-bazaaragent  Build and copy the optional BazaarAgent assemblies.
  --fast              With build: skip NuGet restore (rerun without it after csproj edits or in a fresh worktree).
  -p:Name=Value       Forward an MSBuild property to publish or fetch-data.
  --game-dir PATH     Proton game root containing TheBazaar.exe.
  --skip-build        With proton-install: copy the existing Windows payload only.
  --skip-ffmpeg       With proton-install: do not install bundled Windows ffmpeg.
EOF
}

case "${1:-}" in
    publish)
        shift
        parse_publish_options "$@"
        ;;
    fetch-data)
        shift
        parse_fetch_data_options "$@"
        ;;
    build)
        shift
        parse_build_options "$@"
        ;;
    restore-locks)  restore_locks ;;
    restore-locked) restore_locked ;;
    test)         test_all ;;
    format)       format ;;
    format-check) format_check ;;
    decompile)
        require_steam_branch public
        decompile "$@"
        ;;
    decompile-all)
        require_steam_branch public
        decompile_all
        ;;
    decompile-ptr)
        require_steam_branch public_test_realm
        BPP_DECOMPILE_OUT=./decompiled-vptr decompile "$@"
        ;;
    decompile-all-ptr)
        require_steam_branch public_test_realm
        BPP_DECOMPILE_OUT=./decompiled-vptr decompile_all
        ;;
    snapshot-managed) snapshot_managed ;;
    build-matrix) build_matrix ;;
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
