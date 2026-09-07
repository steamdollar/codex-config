#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const EXPECTED_VERSION = "0.5.1";
const PLUGIN_ID = "agy@agy-staff";
const SEGMENT_PATTERN = /^[A-Za-z0-9._-]+$/;

function fail(message) {
  console.error(`agy-worker: ${message}`);
  process.exitCode = 1;
}

function validateSegment(label, value) {
  if (typeof value !== "string" || !value || !SEGMENT_PATTERN.test(value) || value === "." || value === "..") {
    throw new Error(`invalid ${label} path segment from plugin metadata: ${JSON.stringify(value)}`);
  }
  return value;
}

function codexHome() {
  const configured = process.env.CODEX_HOME;
  if (!configured) return path.join(os.homedir(), ".codex");
  return configured === "~" ? os.homedir() : configured.startsWith("~/") ? path.join(os.homedir(), configured.slice(2)) : configured;
}

function listPlugin() {
  const result = spawnSync("codex", ["plugin", "list", "--marketplace", "agy-staff", "--json"], {
    encoding: "utf8",
  });
  if (result.error) {
    throw new Error(`could not list plugins: ${result.error.message}; ensure the Codex CLI is installed and on PATH`);
  }
  if (result.status !== 0) {
    const detail = (result.stderr || "").trim();
    throw new Error(`plugin list failed with exit ${result.status}${detail ? `: ${detail}` : ""}`);
  }
  let listing;
  try {
    listing = JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`could not parse \`codex plugin list --marketplace agy-staff --json\` output: ${error.message}`);
  }
  if (!listing || !Array.isArray(listing.installed)) {
    throw new Error("plugin list JSON has no installed array; expected Codex plugin list layout");
  }
  const plugin = listing.installed.find((candidate) => candidate && candidate.pluginId === PLUGIN_ID);
  if (!plugin) {
    throw new Error(`installed plugin ${PLUGIN_ID} was not found; install it with \`codex plugin add ${PLUGIN_ID}\``);
  }
  if (plugin.installed !== true) {
    throw new Error(`plugin ${PLUGIN_ID} is not installed; install it with \`codex plugin add ${PLUGIN_ID}\``);
  }
  return plugin;
}

function companionPath(plugin) {
  const marketplace = validateSegment("marketplaceName", plugin.marketplaceName);
  const name = validateSegment("name", plugin.name);
  const version = validateSegment("version", plugin.version);
  if (marketplace !== "agy-staff" || name !== "agy") {
    throw new Error(`plugin ${PLUGIN_ID} metadata layout mismatch: expected marketplaceName=agy-staff and name=agy`);
  }
  if (version !== EXPECTED_VERSION) {
    throw new Error(
      `plugin ${PLUGIN_ID} version ${version} is unsupported; expected ${EXPECTED_VERSION}. ` +
        "Upgrade with `codex plugin marketplace upgrade agy-staff && codex plugin add agy@agy-staff`",
    );
  }
  const companion = path.join(codexHome(), "plugins", "cache", marketplace, name, version, "companion", "agy-companion.mjs");
  if (!existsSync(companion) || !statSync(companion).isFile()) {
    throw new Error(`companion file is missing at ${companion}; reinstall ${PLUGIN_ID} with \`codex plugin add ${PLUGIN_ID}\``);
  }
  return companion;
}

function forward(companion) {
  const child = spawn(process.execPath, [companion, ...process.argv.slice(2)], {
    env: process.env,
    stdio: "inherit",
  });
  child.once("error", (error) => {
    console.error(`agy-worker: could not start companion: ${error.message}`);
    process.exitCode = 1;
  });
  child.once("exit", (code, signal) => {
    if (signal) {
      try {
        process.kill(process.pid, signal);
      } catch {
        process.exitCode = 128;
      }
      return;
    }
    process.exitCode = code ?? 1;
  });
}

try {
  forward(companionPath(listPlugin()));
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
