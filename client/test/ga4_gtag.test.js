import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { init, Ga4Gtag, _resetForTests } from "../src/index.js";

const SAMPLE_MANIFEST = {
  version: "0.2.0",
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
  window.gtag = vi.fn();
});

afterEach(() => {
  delete globalThis.fetch;
  delete window.gtag;
  vi.restoreAllMocks();
});

describe("Ga4Gtag named export — REQ-08 client-side half", () => {
  test("Ga4Gtag.handle dispatches via gtag using the same module state init() populated", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-GA4", manifestUrl: "/m.json" });

    Ga4Gtag.handle("purchase", { value: 19.99, currency: "EUR" });

    const eventCall = window.gtag.mock.calls.find((c) => c[0] === "event");
    expect(eventCall).toEqual(["event", "purchase", { value: 19.99, currency: "EUR" }]);

    const configCall = window.gtag.mock.calls.find((c) => c[0] === "config");
    expect(configCall).toEqual(["config", "G-GA4", {}]);
  });

  test("Ga4Gtag.handle validates against the manifest (dev throws)", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-GA4", manifestUrl: "/m.json", env: "development" });

    expect(() => Ga4Gtag.handle("purchase", { currency: "EUR" })).toThrow(/value/);
  });

  test("Ga4Gtag.handle untyped event passes through (REQ-06)", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-GA4", manifestUrl: "/m.json" });

    Ga4Gtag.handle("first_visit", { source: "newsletter" });

    const eventCall = window.gtag.mock.calls.find((c) => c[0] === "event");
    expect(eventCall).toEqual(["event", "first_visit", { source: "newsletter" }]);
  });

  test("Ga4Gtag exposes a `name` field (parity with server-side Subscribers::Ga4MeasurementProtocol)", () => {
    expect(Ga4Gtag.name).toBe("Ga4Gtag");
  });
});
