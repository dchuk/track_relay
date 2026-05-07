import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { init, track, setClientId, _resetForTests } from "../src/index.js";

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

describe("init() manifestUrl-required contract — 0.3.0 AhoyJs-only support", () => {
  test("init({}) throws synchronously, message mentions manifestUrl only", () => {
    expect(() => init({})).toThrow(/manifestUrl/);
    expect(() => init({})).not.toThrow(/measurementId/);
  });

  test("init() with no argument throws synchronously", () => {
    expect(() => init()).toThrow(/manifestUrl/);
    expect(() => init()).not.toThrow(/measurementId/);
  });

  test("init({ manifestUrl }) — no measurementId — resolves (AhoyJs-only host)", async () => {
    mockFetchManifest();
    await expect(init({ manifestUrl: "/m.json" })).resolves.toBeUndefined();
  });

  test("init({measurementId}) — missing manifestUrl — throws", () => {
    expect(() => init({ measurementId: "G-X" })).toThrow(/manifestUrl/);
    expect(() => init({ measurementId: "G-X" })).not.toThrow(/measurementId/);
  });

  test("init() with empty-string measurementId — manifestUrl present — resolves (AhoyJs-only host)", async () => {
    mockFetchManifest();
    await expect(
      init({ measurementId: "", manifestUrl: "/m.json" })
    ).resolves.toBeUndefined();
  });

  test("init() with nullish measurementId — manifestUrl present — resolves (AhoyJs-only host)", async () => {
    mockFetchManifest();
    await expect(
      init({ measurementId: null, manifestUrl: "/m.json" })
    ).resolves.toBeUndefined();
  });
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

describe("track() validation — REQ-05 mirror", () => {
  test("dev: throws Error including event name + missing key when required param absent", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json", env: "development" });

    expect(() => track("purchase", { currency: "USD" })).toThrow(/purchase.*value/);
  });

  test("prod: console.warn is called and gtag('event') is NOT called when required param absent", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json", env: "production" });

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    track("purchase", { currency: "USD" });

    expect(warnSpy).toHaveBeenCalled();
    const eventCalls = window.gtag.mock.calls.filter((c) => c[0] === "event");
    expect(eventCalls).toHaveLength(0);
  });

  test("dev: throws on wrong type (string for float)", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json", env: "development" });

    expect(() =>
      track("purchase", { value: "not-a-number", currency: "USD" })
    ).toThrow(/value.*float/);
  });

  test("prod: console.warn + drop on wrong type", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json", env: "production" });

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    track("purchase", { value: "not-a-number", currency: "USD" });

    expect(warnSpy).toHaveBeenCalled();
    const eventCalls = window.gtag.mock.calls.filter((c) => c[0] === "event");
    expect(eventCalls).toHaveLength(0);
  });

  test("missing window.gtag — warn + drop, never throw", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json" });

    delete window.gtag;
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    expect(() => track("purchase", { value: 1, currency: "USD" })).not.toThrow();
    expect(warnSpy).toHaveBeenCalledWith(expect.stringMatching(/window\.gtag not found/));
  });

  test("extra params not in schema — allowed, pass through without warning", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-TEST", manifestUrl: "/m.json", env: "development" });

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    expect(() =>
      track("purchase", { value: 9.99, currency: "USD", extra_field: "ignored" })
    ).not.toThrow();
    expect(warnSpy).not.toHaveBeenCalled();

    const eventCall = window.gtag.mock.calls.find((c) => c[0] === "event");
    expect(eventCall[2]).toEqual({ value: 9.99, currency: "USD", extra_field: "ignored" });
  });

  test("onValidationError callback fires with error array (prod, drops event)", async () => {
    mockFetchManifest();
    const cb = vi.fn();
    await init({
      measurementId: "G-TEST",
      manifestUrl: "/m.json",
      env: "production",
      onValidationError: cb
    });

    track("purchase", { currency: "USD" });

    expect(cb).toHaveBeenCalledTimes(1);
    expect(cb.mock.calls[0][0]).toEqual(expect.arrayContaining([expect.stringMatching(/value/)]));
  });

  test("integer type accepts numbers without fractional component", async () => {
    mockFetchManifest({
      version: "0.2.0",
      generated_at: "2026-05-06T00:00:00Z",
      events: { tally: { params: { count: "integer" }, required: ["count"] } }
    });
    await init({ measurementId: "G-T", manifestUrl: "/m.json", env: "development" });

    expect(() => track("tally", { count: 5 })).not.toThrow();
    expect(() => track("tally", { count: 5.5 })).toThrow(/count.*integer/);
  });

  test("boolean type accepts true/false only", async () => {
    mockFetchManifest({
      version: "0.2.0",
      generated_at: "2026-05-06T00:00:00Z",
      events: { flag: { params: { on: "boolean" }, required: ["on"] } }
    });
    await init({ measurementId: "G-T", manifestUrl: "/m.json", env: "development" });

    expect(() => track("flag", { on: true })).not.toThrow();
    expect(() => track("flag", { on: "true" })).toThrow(/on.*boolean/);
  });

  test("gtag('config', measurementId, {client_id}) fires once per page lifecycle", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-PAGELIFE", manifestUrl: "/m.json" });
    setClientId("123.456");

    track("purchase", { value: 1, currency: "USD" });
    track("purchase", { value: 2, currency: "USD" });
    track("purchase", { value: 3, currency: "USD" });

    const configCalls = window.gtag.mock.calls.filter((c) => c[0] === "config");
    expect(configCalls).toHaveLength(1);
    expect(configCalls[0]).toEqual(["config", "G-PAGELIFE", { client_id: "123.456" }]);

    const eventCalls = window.gtag.mock.calls.filter((c) => c[0] === "event");
    expect(eventCalls).toHaveLength(3);
  });

  test("setClientId() AFTER init causes the next track() to re-emit gtag('config')", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-RECONFIG", manifestUrl: "/m.json" });

    track("purchase", { value: 1, currency: "USD" }); // flushes config with no client_id
    setClientId("999.000");
    track("purchase", { value: 2, currency: "USD" }); // re-flushes with new client_id

    const configCalls = window.gtag.mock.calls.filter((c) => c[0] === "config");
    expect(configCalls).toHaveLength(2);
    expect(configCalls[0]).toEqual(["config", "G-RECONFIG", {}]);
    expect(configCalls[1]).toEqual(["config", "G-RECONFIG", { client_id: "999.000" }]);
  });

  test("datetime type accepts ISO8601 string or Date instance", async () => {
    mockFetchManifest({
      version: "0.2.0",
      generated_at: "2026-05-06T00:00:00Z",
      events: { tick: { params: { at: "datetime" }, required: ["at"] } }
    });
    await init({ measurementId: "G-T", manifestUrl: "/m.json", env: "development" });

    expect(() => track("tick", { at: "2026-05-06T12:00:00Z" })).not.toThrow();
    expect(() => track("tick", { at: new Date() })).not.toThrow();
    expect(() => track("tick", { at: "not-a-date" })).toThrow(/at.*datetime/);
  });
});
