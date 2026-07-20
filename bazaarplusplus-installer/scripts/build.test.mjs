import { test, expect } from "vitest";
import { execFileSync } from "node:child_process";

const projectDir = process.cwd();
const bashCommand = "bash";

function runShell(script) {
  return execFileSync(bashCommand, ["-lc", script], {
    cwd: projectDir,
    encoding: "utf8",
    timeout: 120000,
  });
}

test("Linux production build uses the linux config without bundling", () => {
  const output = runShell(`
    set -euo pipefail
    source ./build.sh
    assert_file() { :; }
    invoke_step() {
      local label="$1"
      shift
      printf '%s|%s\\n' "$label" "$*"
    }
    build_prod
  `);

  expect(output).toMatch(
    /Building Linux app binary\|npm run tauri build -- --no-bundle --config .*src-tauri\/tauri\.linux\.conf\.json/,
  );
  expect(output).toMatch(
    /Binary:\s+.*src-tauri\/target\/release\/bppinstaller/,
  );
});

test("release prechecks build the Linux Proton payload zip first", () => {
  const output = runShell(`
    set -euo pipefail
    source ./build.sh
    prepare_linux_resource_zip() {
      printf 'prepare_linux_resource_zip\\n'
    }
    invoke_step() {
      local label="$1"
      shift
      printf '%s|%s\\n' "$label" "$*"
    }
    run_release_prechecks
  `);

  expect(output).toMatch(/prepare_linux_resource_zip/);
  expect(output).toMatch(
    /Synchronizing package versions\|node scripts\/version-sync\.mjs/,
  );
  expect(output).toMatch(
    /Running prebuild checks\|env TAURI_ENV_PLATFORM=linux npm run prebuild-check/,
  );
});

test("Linux build resources come from the Proton payload source", () => {
  const output = runShell(`
    set -euo pipefail
    source ./build.sh
    printf 'proton=%s\\n' "$PROTON_PAYLOAD_SOURCE"
    if [[ -n "\${WINDOWS_PAYLOAD_SOURCE+x}" ]]; then
      printf 'legacy-windows=%s\\n' "$WINDOWS_PAYLOAD_SOURCE"
    fi
  `);

  expect(output).toMatch(
    /proton=.*src-tauri\/resources\/SourceForBuild\/proton/,
  );
  expect(output).not.toMatch(/legacy-windows=/);
});
