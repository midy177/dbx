import { chmodSync, copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const rootDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const zigCacheDir = join(rootDir, "target", "zig-cache");
const toolEnv = {
  ...process.env,
  RUSTFLAGS: appendRustflags(process.env.RUSTFLAGS, "-A linker-messages"),
  RUST_FONTCONFIG_DLOPEN: process.env.RUST_FONTCONFIG_DLOPEN ?? "1",
  ZIG_GLOBAL_CACHE_DIR: process.env.ZIG_GLOBAL_CACHE_DIR ?? join(zigCacheDir, "global"),
  ZIG_LOCAL_CACHE_DIR: process.env.ZIG_LOCAL_CACHE_DIR ?? join(zigCacheDir, "local"),
};

const targets = new Map([
  [
    "linux/amd64",
    {
      rustTarget: "x86_64-unknown-linux-gnu",
      outputDir: join(rootDir, "dist", "docker", "linux", "amd64"),
    },
  ],
  [
    "linux/arm64",
    {
      rustTarget: "aarch64-unknown-linux-gnu",
      outputDir: join(rootDir, "dist", "docker", "linux", "arm64"),
    },
  ],
]);

const options = parseArgs(process.argv.slice(2));

if (options.help) {
  console.log(`Usage: node scripts/build-web-prebuilt.mjs [options]

Options:
  --platforms <list>   Comma-separated platforms. Default: linux/amd64,linux/arm64
  --platform <value>   Single platform, for example linux/amd64
  --skip-frontend      Reuse the existing dist/ frontend output
  --help               Show this help
`);
  process.exit(0);
}

const platforms = options.platforms.length > 0 ? options.platforms : ["linux/amd64", "linux/arm64"];

for (const platform of platforms) {
  if (!targets.has(platform)) {
    fail(`Unsupported platform "${platform}". Supported platforms: ${[...targets.keys()].join(", ")}`);
  }
}

mkdirSync(toolEnv.ZIG_GLOBAL_CACHE_DIR, { recursive: true });
mkdirSync(toolEnv.ZIG_LOCAL_CACHE_DIR, { recursive: true });

run("cargo", ["zigbuild", "--help"], {
  env: toolEnv,
  failureHint: "cargo-zigbuild is required. Install it with: cargo install cargo-zigbuild",
  quiet: true,
});

if (!options.skipFrontend) {
  run("bun", ["run", "build"], {
    env: {
      ...toolEnv,
      DBX_PUBLIC_BASE_PATH: toolEnv.DBX_PUBLIC_BASE_PATH ?? "/",
    },
  });
} else if (!existsSync(join(rootDir, "dist", "index.html"))) {
  fail("dist/index.html does not exist. Run without --skip-frontend first.");
}

for (const platform of platforms) {
  const target = targets.get(platform);
  console.log(`\nBuilding ${platform} (${target.rustTarget})`);

  run("rustup", ["target", "add", target.rustTarget], { env: toolEnv });
  run(
    "cargo",
    [
      "zigbuild",
      "--release",
      "-p",
      "dbx-web",
      "--features",
      "embedded-static",
      "--target",
      target.rustTarget,
    ],
    { env: toolEnv },
  );

  const source = join(rootDir, "target", target.rustTarget, "release", "dbx-web");
  const destination = join(target.outputDir, "dbx-web");
  mkdirSync(target.outputDir, { recursive: true });
  copyFileSync(source, destination);
  chmodSync(destination, 0o755);
  console.log(`Wrote ${relativeToRoot(destination)}`);
}

function parseArgs(args) {
  const parsed = {
    help: false,
    platforms: splitPlatformList(process.env.PLATFORM ?? process.env.PREBUILT_PLATFORMS ?? ""),
    skipFrontend: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--help" || arg === "-h") {
      parsed.help = true;
    } else if (arg === "--skip-frontend") {
      parsed.skipFrontend = true;
    } else if (arg === "--platform" || arg === "--platforms") {
      const value = args[index + 1];
      if (!value) fail(`${arg} requires a value`);
      parsed.platforms = splitPlatformList(value);
      index += 1;
    } else if (arg.startsWith("--platform=")) {
      parsed.platforms = splitPlatformList(arg.slice("--platform=".length));
    } else if (arg.startsWith("--platforms=")) {
      parsed.platforms = splitPlatformList(arg.slice("--platforms=".length));
    } else {
      fail(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

function splitPlatformList(value) {
  return value
    .split(",")
    .map((platform) => platform.trim())
    .filter(Boolean);
}

function appendRustflags(current, value) {
  return [current, value].filter(Boolean).join(" ");
}

function run(command, args, options = {}) {
  if (!options.quiet) {
    console.log(`$ ${[command, ...args].join(" ")}`);
  }
  const result = spawnSync(command, args, {
    cwd: rootDir,
    env: options.env ?? process.env,
    stdio: options.quiet ? "ignore" : "inherit",
  });

  if (result.error) {
    const hint = options.failureHint ? `\n${options.failureHint}` : "";
    fail(`${command} failed to start: ${result.error.message}${hint}`);
  }

  if (result.status !== 0) {
    const hint = options.failureHint ? `\n${options.failureHint}` : "";
    fail(`${command} exited with status ${result.status}${hint}`);
  }
}

function relativeToRoot(path) {
  return path.startsWith(rootDir) ? path.slice(rootDir.length + 1) : path;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
