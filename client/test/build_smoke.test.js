import { describe, test, expect } from "vitest";
import { readFileSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const distDir = resolve(__dirname, "..", "dist");
const mjsPath = resolve(distDir, "index.mjs");
const cjsPath = resolve(distDir, "index.cjs");

// This suite asserts that `npm run build` produced REAL dual ESM+CJS
// artifacts. The CI job (and the local `npm run build && npm test`
// workflow) runs the build before tests, so this is a regression guard
// against accidentally shipping an ESM file under a `.cjs` extension —
// which would crash any `require("@track_relay/client")` consumer.
describe("dual-format build artifacts", () => {
  test("dist/index.mjs exists and is non-empty", () => {
    expect(existsSync(mjsPath)).toBe(true);
    expect(statSync(mjsPath).size).toBeGreaterThan(0);
  });

  test("dist/index.cjs exists and is non-empty", () => {
    expect(existsSync(cjsPath)).toBe(true);
    expect(statSync(cjsPath).size).toBeGreaterThan(0);
  });

  test("dist/index.mjs is a real ES module (contains `export`)", () => {
    const contents = readFileSync(mjsPath, "utf8");
    expect(contents).toMatch(/\bexport\b/);
  });

  test("dist/index.cjs is real CommonJS (contains module.exports / exports.X)", () => {
    const contents = readFileSync(cjsPath, "utf8");
    // tsup emits either `module.exports = ...` or `exports.foo = ...` for CJS.
    expect(contents).toMatch(/module\.exports|exports\.[A-Za-z_$]/);
  });
});
