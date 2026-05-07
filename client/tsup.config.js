// tsup config — produces real dual ESM (.mjs) + CJS (.cjs) artifacts from
// plain JS sources. Honors the 02-CONTEXT line 52 commitment: consumers
// using `require("@track_relay/client")` get a real CommonJS module, not
// an ESM file with a misleading extension.
export default {
  entry: ["src/index.js"],
  format: ["esm", "cjs"],
  outDir: "dist",
  outExtension: ({ format }) => ({ js: format === "esm" ? ".mjs" : ".cjs" }),
  target: "es2020",
  clean: true,
  splitting: false,
  sourcemap: false,
  dts: false,
  minify: false
};
