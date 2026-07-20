#!/usr/bin/env bash
set -euo pipefail

PROD=false
CLEAN_DEPS=false

usage() {
    cat <<'EOF'
Usage:
  ./build.sh
      Start the local Linux Tauri dev app.

  ./build.sh --prod
      Build the local Linux Tauri app binary after refreshing the Proton payload
      resource zip and running prebuild checks.

  ./build.sh --prod --clean-deps
      Reinstall npm dependencies before building.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_CONFIG="$SCRIPT_DIR/src-tauri/tauri.linux.conf.json"
LINUX_ZIP="$SCRIPT_DIR/src-tauri/resources/BepInExSource/linux/BepInEx.zip"
PROTON_PAYLOAD_SOURCE="$SCRIPT_DIR/src-tauri/resources/SourceForBuild/proton"

assert_command() {
    local name="$1"
    local hint="${2:-}"
    if ! command -v "$name" &>/dev/null; then
        if [ -n "$hint" ]; then
            echo "Error: $name not found. $hint" >&2
        else
            echo "Error: $name not found." >&2
        fi
        exit 1
    fi
}

assert_file() {
    local path="$1"
    local label="$2"
    if [ ! -f "$path" ]; then
        echo "Error: Missing $label: $path" >&2
        exit 1
    fi
}

invoke_step() {
    local label="$1"
    shift
    echo "==> $label"
    "$@"
}

assert_proton_payload_ready() {
    local files=(
        winhttp.dll
        doorstop_config.ini
        BepInEx/plugins/BazaarPlusPlus.dll
        BepInEx/plugins/BazaarPlusPlus.version
        BepInEx/plugins/BazaarPlusPlus.ModApi.dll
        BepInEx/plugins/BazaarPlusPlus.Localization.dll
        BepInEx/plugins/BazaarPlusPlus.Storage.dll
        BepInEx/plugins/BazaarPlusPlus.BazaarAgent.dll
        BepInEx/plugins/BazaarPlusPlus.BazaarAgentHost.dll
    )
    local missing=()
    local file

    for file in "${files[@]}"; do
        if [ ! -f "$PROTON_PAYLOAD_SOURCE/$file" ]; then
            missing+=("$file")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        return
    fi

    echo "Error: Proton payload source is incomplete: $PROTON_PAYLOAD_SOURCE" >&2
    printf '  missing: %s\n' "${missing[@]}" >&2
    echo >&2
    echo "Build the mod payload first with .NET SDK 8+ and a local Proton game install:" >&2
    echo "  cd \"$SCRIPT_DIR/../bazaarplusplus-mod\"" >&2
    echo "  ./run.sh build-payload --game-dir \"/path/to/steamapps/common/The Bazaar\"" >&2
    exit 1
}

create_zip_from_directory() {
    local source_dir="$1"
    local output_zip="$2"

    mkdir -p "$(dirname "$output_zip")"
    if command -v zip &>/dev/null; then
        (
            cd "$source_dir"
            zip -qry -X "$output_zip" .
        )
    elif command -v 7z &>/dev/null; then
        rm -f "$output_zip"
        (
            cd "$source_dir"
            7z a -tzip -mx=9 "$output_zip" . >/dev/null
        )
    else
        echo "Error: zip or 7z not found. Install one before building." >&2
        exit 1
    fi
}

prepare_linux_resource_zip() {
    assert_proton_payload_ready

    invoke_step "Preparing Linux/Proton resource zip" \
        create_zip_from_directory "$PROTON_PAYLOAD_SOURCE" "$LINUX_ZIP"
}

install_dependencies() {
    if [ "$CLEAN_DEPS" = false ] \
        && [ -d "$SCRIPT_DIR/node_modules" ] \
        && [ -d "$SCRIPT_DIR/node_modules/@tauri-apps/cli" ] \
        && { [ -f "$SCRIPT_DIR/node_modules/.bin/tauri" ] || [ -f "$SCRIPT_DIR/node_modules/.bin/tauri.cmd" ]; } \
        && npm ls --depth=0 >/dev/null 2>&1; then
        echo "==> Reusing existing npm dependencies"
        echo "    Remove node_modules or rerun with --clean-deps to force a reinstall."
        return
    fi

    if [ "$CLEAN_DEPS" = true ] && [ -f "$SCRIPT_DIR/package-lock.json" ]; then
        invoke_step "Installing npm dependencies" npm ci
    else
        invoke_step "Installing npm dependencies" npm install
    fi
}

run_release_prechecks() {
    prepare_linux_resource_zip
    invoke_step "Synchronizing package versions" node scripts/version-sync.mjs
    invoke_step "Running prebuild checks" env TAURI_ENV_PLATFORM=linux npm run prebuild-check
}

build_prod() {
    assert_file "$LINUX_CONFIG" "Linux Tauri config"
    assert_file "$LINUX_ZIP" "Linux resource zip"

    invoke_step "Building Linux app binary" \
        npm run tauri build -- --no-bundle --config "$LINUX_CONFIG"

    echo
    echo "Build complete."
    echo "Binary:  $SCRIPT_DIR/src-tauri/target/release/bppinstaller"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --prod)
                PROD=true
                ;;
            --clean-deps)
                CLEAN_DEPS=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"

    cd "$SCRIPT_DIR"

    assert_command node "Install Node.js first."
    assert_command npm "Install Node.js/npm first."
    assert_command cargo "Install Rust toolchain first."
    install_dependencies

    if [ "$PROD" = false ]; then
        invoke_step "Starting dev server" npm run tauri dev
        exit 0
    fi

    run_release_prechecks
    build_prod
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
