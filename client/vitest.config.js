// Vitest config — happy-dom gives us window/document/fetch globals so the
// JS client can be tested against browser-like APIs without spinning up a
// real browser. Tests run against `src/` directly for fast feedback;
// `test/build_smoke.test.js` is the single place that asserts `dist/`
// artifacts exist after `npm run build`.
export default {
  test: {
    environment: "happy-dom",
    globals: false,
    include: ["test/**/*.test.js"]
  }
};
