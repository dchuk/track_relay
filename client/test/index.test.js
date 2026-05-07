import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { init, track, _resetForTests } from "../src/index.js";

const SAMPLE_MANIFEST = {
  version: "0.2.0",
  generated_at: "2026-05-06T00:00:00Z",
  events: {
    purchase: {
      params: { value: "float", currency: "string", coupon: "string" },
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

describe("init() happy path", () => {
  test("fetches the manifest URL and stores state for subsequent track() calls", async () => {
    mockFetchManifest();

    await init({ measurementId: "G-TEST", manifestUrl: "/manifest.json" });

    expect(globalThis.fetch).toHaveBeenCalledWith("/manifest.json");

    track("purchase", { value: 9.99, currency: "USD" });

    // First call wires client_id via gtag('config', ...), second is the event.
    const eventCall = window.gtag.mock.calls.find((c) => c[0] === "event");
    expect(eventCall).toEqual(["event", "purchase", { value: 9.99, currency: "USD" }]);
  });

  test("init() rejects when fetch rejects so callers can .catch()", async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error("network down"));

    await expect(
      init({ measurementId: "G-TEST", manifestUrl: "/manifest.json" })
    ).rejects.toThrow("network down");
  });

  test("init() rejects when fetch returns non-OK status", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 404,
      json: vi.fn()
    });

    await expect(
      init({ measurementId: "G-TEST", manifestUrl: "/missing.json" })
    ).rejects.toThrow(/manifest fetch failed.*404/);
  });
});

describe("track() pass-through behavior", () => {
  test("untyped event (not in manifest) passes through to gtag — REQ-06", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json" });

    track("custom_unlisted_event", { foo: "bar" });

    const eventCall = window.gtag.mock.calls.find((c) => c[0] === "event");
    expect(eventCall).toEqual(["event", "custom_unlisted_event", { foo: "bar" }]);
  });

  test("track() with no params dispatches an empty params object", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json" });

    track("ping");

    const eventCall = window.gtag.mock.calls.find((c) => c[0] === "event");
    expect(eventCall).toEqual(["event", "ping", {}]);
  });
});
