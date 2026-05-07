import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { init, AhoyJs, _resetForTests } from "../src/index.js";

const SAMPLE_MANIFEST = {
  version: "0.3.0",
  generated_at: "2026-05-06T00:00:00Z",
  events: {
    purchase: {
      params: { value: "float", currency: "string" },
      required: ["value", "currency"]
    }
  }
};

function mockFetchManifest(manifest = SAMPLE_MANIFEST) {
  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: true,
    json: vi.fn().mockResolvedValue(manifest)
  });
}

beforeEach(() => {
  _resetForTests();
  // AhoyJs dispatches via window.ahoy.track — mirrors how Ga4Gtag tests
  // wire up window.gtag.
  window.ahoy = { track: vi.fn() };
});

afterEach(() => {
  delete globalThis.fetch;
  delete window.ahoy;
  vi.restoreAllMocks();
});

describe("AhoyJs named export — REQ-09 client-side half", () => {
  test("AhoyJs.handle dispatches via window.ahoy.track after init({ manifestUrl }) (no measurementId)", async () => {
    mockFetchManifest();
    // Critical 0.3.0 contract: AhoyJs-only host can init without measurementId.
    await init({ manifestUrl: "/m.json" });

    AhoyJs.handle("purchase", { value: 19.99, currency: "EUR" });

    expect(window.ahoy.track).toHaveBeenCalledTimes(1);
    expect(window.ahoy.track).toHaveBeenCalledWith("purchase", {
      value: 19.99,
      currency: "EUR"
    });
  });

  test("typed event with missing required param in env=development throws", async () => {
    mockFetchManifest();
    await init({ manifestUrl: "/m.json", env: "development" });

    expect(() => AhoyJs.handle("purchase", { currency: "EUR" })).toThrow(
      /purchase.*value/
    );
    // No dispatch when validation fails.
    expect(window.ahoy.track).not.toHaveBeenCalled();
  });

  test("typed event with missing required param in env=production warns + drops", async () => {
    mockFetchManifest();
    await init({ manifestUrl: "/m.json", env: "production" });

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    AhoyJs.handle("purchase", { currency: "EUR" });

    expect(warnSpy).toHaveBeenCalled();
    expect(window.ahoy.track).not.toHaveBeenCalled();
  });

  test("untyped event (not in manifest) passes through to window.ahoy.track — REQ-06 client-side parity", async () => {
    mockFetchManifest();
    await init({ manifestUrl: "/m.json" });

    AhoyJs.handle("first_visit", { source: "newsletter" });

    expect(window.ahoy.track).toHaveBeenCalledTimes(1);
    expect(window.ahoy.track).toHaveBeenCalledWith("first_visit", {
      source: "newsletter"
    });
  });

  test("when window.ahoy is undefined, console.warn is called and no exception is raised", async () => {
    mockFetchManifest();
    await init({ manifestUrl: "/m.json" });

    delete window.ahoy;
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    expect(() =>
      AhoyJs.handle("first_visit", { source: "newsletter" })
    ).not.toThrow();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringMatching(/window\.ahoy\.track not found/)
    );
  });

  test("AhoyJs.name === 'AhoyJs' (parity with Ga4Gtag.name)", () => {
    expect(AhoyJs.name).toBe("AhoyJs");
  });
});
