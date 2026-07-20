import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test, expect } from "vitest";

import {
  assertBindingsUpToDate,
  diffGeneratedFileSnapshots,
  requiredEntriesForPlatform,
  resolveTargetPlatforms,
} from "./prebuild-check.mjs";

test("Linux bundles BazaarPlusPlus SQLite dependencies", () => {
  expect(requiredEntriesForPlatform("linux")).toEqual([
    "winhttp.dll",
    "doorstop_config.ini",
    "BepInEx/plugins/BazaarPlusPlus.dll",
    "BepInEx/plugins/BazaarPlusPlus.version",
    "BepInEx/plugins/BazaarPlusPlus.ModApi.dll",
    "BepInEx/plugins/BazaarPlusPlus.Localization.dll",
    "BepInEx/plugins/BazaarPlusPlus.Storage.dll",
    "BepInEx/plugins/BazaarPlusPlus.BazaarAgent.dll",
    "BepInEx/plugins/BazaarPlusPlus.BazaarAgentHost.dll",
    "BepInEx/plugins/Microsoft.Data.Sqlite.dll",
    "BepInEx/plugins/SQLitePCLRaw.batteries_v2.dll",
    "BepInEx/plugins/SQLitePCLRaw.core.dll",
    "BepInEx/plugins/SQLitePCLRaw.provider.e_sqlite3.dll",
    "BepInEx/plugins/SixLabors.ImageSharp.dll",
    "BepInEx/plugins/System.Buffers.dll",
    "BepInEx/plugins/System.Memory.dll",
    "BepInEx/plugins/System.Numerics.Vectors.dll",
    "BepInEx/plugins/System.Text.Encoding.CodePages.dll",
    "BepInEx/plugins/e_sqlite3.dll",
  ]);
});

test("prebuild check only targets Linux", () => {
  expect(resolveTargetPlatforms(undefined)).toEqual(["linux"]);
  expect(resolveTargetPlatforms("linux")).toEqual(["linux"]);
  expect(() => resolveTargetPlatforms("win32")).toThrow(
    /Unsupported TAURI_ENV_PLATFORM value: win32/,
  );
  expect(() => resolveTargetPlatforms("darwin")).toThrow(
    /Unsupported TAURI_ENV_PLATFORM value: darwin/,
  );
});

test("generated bindings check allows pre-existing dirty generated files", () => {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "bpp-prebuild-"));
  const generatedDir = path.join(rootDir, "src/types/generated");
  fs.mkdirSync(generatedDir, { recursive: true });
  fs.writeFileSync(path.join(generatedDir, "index.ts"), "dirty baseline");

  try {
    expect(() => assertBindingsUpToDate(rootDir, () => {})).not.toThrow();
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
});

test("generated bindings check reports files changed by generation", () => {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "bpp-prebuild-"));
  const generatedDir = path.join(rootDir, "src/types/generated");
  fs.mkdirSync(generatedDir, { recursive: true });
  fs.writeFileSync(path.join(generatedDir, "index.ts"), "old");

  try {
    expect(() =>
      assertBindingsUpToDate(rootDir, () => {
        fs.writeFileSync(path.join(generatedDir, "index.ts"), "new");
        fs.writeFileSync(path.join(generatedDir, "NewType.ts"), "new type");
      }),
    ).toThrow(
      /M src\/types\/generated\/index\.ts[\s\S]*\?\? src\/types\/generated\/NewType\.ts/,
    );
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
});

test("generated snapshot diff reports deletions", () => {
  expect(
    diffGeneratedFileSnapshots(
      [{ path: "src/types/generated/OldType.ts", hash: "before" }],
      [],
    ),
  ).toEqual(["D src/types/generated/OldType.ts"]);
});
