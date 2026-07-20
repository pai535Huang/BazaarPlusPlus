import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import zlib from "node:zlib";
import {
  assertVersionsAreAligned,
  collectVersionSnapshot,
} from "./version-sync.mjs";

export const sharedBundledZipPath = "BepInExSource/BepInEx.zip";

const managedPluginDependencies = [
  "BepInEx/plugins/Microsoft.Data.Sqlite.dll",
  "BepInEx/plugins/SQLitePCLRaw.batteries_v2.dll",
  "BepInEx/plugins/SQLitePCLRaw.core.dll",
  "BepInEx/plugins/SQLitePCLRaw.provider.e_sqlite3.dll",
  "BepInEx/plugins/SixLabors.ImageSharp.dll",
  "BepInEx/plugins/System.Buffers.dll",
  "BepInEx/plugins/System.Memory.dll",
  "BepInEx/plugins/System.Numerics.Vectors.dll",
  "BepInEx/plugins/System.Text.Encoding.CodePages.dll",
];

export function resolveTargetPlatforms(platformEnv) {
  if (!platformEnv) {
    return ["linux"];
  }

  if (platformEnv !== "linux") {
    throw new Error(`Unsupported TAURI_ENV_PLATFORM value: ${platformEnv}`);
  }

  return ["linux"];
}

export function requiredEntriesForPlatform(platform) {
  if (platform === "linux") {
    return [
      "winhttp.dll",
      "doorstop_config.ini",
      "BepInEx/plugins/BazaarPlusPlus.dll",
      "BepInEx/plugins/BazaarPlusPlus.version",
      "BepInEx/plugins/BazaarPlusPlus.ModApi.dll",
      "BepInEx/plugins/BazaarPlusPlus.Localization.dll",
      "BepInEx/plugins/BazaarPlusPlus.Storage.dll",
      "BepInEx/plugins/BazaarPlusPlus.BazaarAgent.dll",
      "BepInEx/plugins/BazaarPlusPlus.BazaarAgentHost.dll",
      ...managedPluginDependencies,
      "BepInEx/plugins/e_sqlite3.dll",
    ];
  }

  throw new Error(`Unsupported platform: ${platform}`);
}

function sourceZipPathForPlatform(rootDir, platform) {
  return path.join(
    rootDir,
    "src-tauri",
    "resources",
    "BepInExSource",
    platform,
    "BepInEx.zip",
  );
}

function findEndOfCentralDirectory(buffer) {
  for (let offset = buffer.length - 22; offset >= 0; offset -= 1) {
    if (buffer.readUInt32LE(offset) === 0x06054b50) {
      return offset;
    }
  }

  throw new Error("Zip end-of-central-directory record not found");
}

export function listZipEntries(buffer) {
  const eocdOffset = findEndOfCentralDirectory(buffer);
  const centralDirectorySize = buffer.readUInt32LE(eocdOffset + 12);
  const centralDirectoryOffset = buffer.readUInt32LE(eocdOffset + 16);
  const endOffset = centralDirectoryOffset + centralDirectorySize;
  const entries = [];

  let cursor = centralDirectoryOffset;
  while (cursor < endOffset) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) {
      throw new Error(`Invalid central directory header at offset ${cursor}`);
    }

    const fileNameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const fileNameStart = cursor + 46;
    const fileNameEnd = fileNameStart + fileNameLength;

    entries.push(buffer.toString("utf8", fileNameStart, fileNameEnd));
    cursor = fileNameEnd + extraLength + commentLength;
  }

  return entries;
}

export function readZipEntry(buffer, entryName) {
  const eocdOffset = findEndOfCentralDirectory(buffer);
  const centralDirectoryOffset = buffer.readUInt32LE(eocdOffset + 16);
  const centralDirectorySize = buffer.readUInt32LE(eocdOffset + 12);
  const endOffset = centralDirectoryOffset + centralDirectorySize;

  let cursor = centralDirectoryOffset;
  while (cursor < endOffset) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) break;

    const fileNameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const localHeaderOffset = buffer.readUInt32LE(cursor + 42);
    const fileNameStart = cursor + 46;
    const fileName = buffer.toString(
      "utf8",
      fileNameStart,
      fileNameStart + fileNameLength,
    );

    if (fileName === entryName || fileName.endsWith(`/${entryName}`)) {
      const compressionMethod = buffer.readUInt16LE(localHeaderOffset + 8);
      const compressedSize = buffer.readUInt32LE(localHeaderOffset + 18);
      const localFileNameLength = buffer.readUInt16LE(localHeaderOffset + 26);
      const localExtraLength = buffer.readUInt16LE(localHeaderOffset + 28);
      const dataStart =
        localHeaderOffset + 30 + localFileNameLength + localExtraLength;
      const compressedData = buffer.subarray(
        dataStart,
        dataStart + compressedSize,
      );

      if (compressionMethod === 0) return compressedData.toString("utf8");
      if (compressionMethod === 8)
        return zlib.inflateRawSync(compressedData).toString("utf8");
      throw new Error(
        `Unsupported compression method ${compressionMethod} for ${entryName}`,
      );
    }

    cursor = fileNameStart + fileNameLength + extraLength + commentLength;
  }

  return null;
}

function ensureZipLooksValid(rootDir, zipPath, platform) {
  if (!fs.existsSync(zipPath)) {
    throw new Error(`Missing ${platform} zip: ${zipPath}`);
  }

  const stats = fs.statSync(zipPath);
  if (!stats.isFile() || stats.size === 0) {
    throw new Error(`Invalid ${platform} zip: ${zipPath}`);
  }

  const buffer = fs.readFileSync(zipPath);
  const entries = listZipEntries(buffer);
  for (const requiredEntry of requiredEntriesForPlatform(platform)) {
    const present = entries.some(
      (entry) => entry === requiredEntry || entry.endsWith(`/${requiredEntry}`),
    );
    if (!present) {
      throw new Error(
        `${platform} zip is missing required entry '${requiredEntry}' in ${zipPath}`,
      );
    }
  }

  const version = readZipEntry(buffer, "BazaarPlusPlus.version");
  if (version) {
    console.log(`[${platform}] BazaarPlusPlus.version: ${version.trim()}`);
  }
}

const generatedTypesDir = "src/types/generated";

export function collectGeneratedFileSnapshot(rootDir) {
  const generatedRoot = path.join(rootDir, generatedTypesDir);
  if (!fs.existsSync(generatedRoot)) {
    return [];
  }

  const files = [];

  function visit(directory) {
    const entries = fs.readdirSync(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name));

    for (const entry of entries) {
      const absolutePath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(absolutePath);
        continue;
      }

      if (!entry.isFile()) {
        continue;
      }

      const relativePath = path
        .relative(rootDir, absolutePath)
        .split(path.sep)
        .join("/");
      const hash = crypto
        .createHash("sha256")
        .update(fs.readFileSync(absolutePath))
        .digest("hex");
      files.push({ path: relativePath, hash });
    }
  }

  visit(generatedRoot);
  return files;
}

export function diffGeneratedFileSnapshots(before, after) {
  const beforeByPath = new Map(before.map((file) => [file.path, file.hash]));
  const afterByPath = new Map(after.map((file) => [file.path, file.hash]));
  const paths = [
    ...new Set([...beforeByPath.keys(), ...afterByPath.keys()]),
  ].sort((left, right) => left.localeCompare(right));

  return paths.flatMap((filePath) => {
    if (!beforeByPath.has(filePath)) {
      return [`?? ${filePath}`];
    }

    if (!afterByPath.has(filePath)) {
      return [`D ${filePath}`];
    }

    return beforeByPath.get(filePath) === afterByPath.get(filePath)
      ? []
      : [`M ${filePath}`];
  });
}

export function npmExecFileInvocation(
  args,
  _platform = process.platform,
  _env = process.env,
) {
  return { command: "npm", args };
}

export function assertBindingsUpToDate(rootDir, execFile = execFileSync) {
  console.log("Checking TypeScript bindings...");
  const before = collectGeneratedFileSnapshot(rootDir);
  const npmInvocation = npmExecFileInvocation(["run", "generate:bindings"]);

  execFile(npmInvocation.command, npmInvocation.args, {
    cwd: rootDir,
    stdio: "inherit",
  });

  const changedFiles = diffGeneratedFileSnapshots(
    before,
    collectGeneratedFileSnapshot(rootDir),
  );

  if (changedFiles.length > 0) {
    throw new Error(
      `Generated TypeScript bindings are out of date under ${generatedTypesDir}. ` +
        "Run npm run generate:bindings and commit all files under that directory.\n" +
        changedFiles.join("\n"),
    );
  }
}

export function runPrebuildCheck(rootDir, platformEnv) {
  console.log("Running prebuild check...");
  assertBindingsUpToDate(rootDir);
  const snapshot = collectVersionSnapshot(rootDir);
  assertVersionsAreAligned(snapshot);
  const platforms = resolveTargetPlatforms(platformEnv);

  for (const platform of platforms) {
    ensureZipLooksValid(
      rootDir,
      sourceZipPathForPlatform(rootDir, platform),
      platform,
    );
  }
}

const invokedAsScript =
  process.argv[1] && path.resolve(process.argv[1]) === import.meta.filename;

if (invokedAsScript) {
  try {
    runPrebuildCheck(process.cwd(), process.env.TAURI_ENV_PLATFORM);
    console.log("prebuild-check: ok");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`prebuild-check: ${message}`);
    process.exit(1);
  }
}
