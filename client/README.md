# @track_relay/client

Client-side event tracker for the [`track_relay`](https://github.com/dchuk/track_relay) Rails gem. Fetches the typed JSON manifest produced by the gem's `rake track_relay:manifest` task, validates events against it, and dispatches them via `window.gtag` (GA4).

The catalog is defined once in Rails. The manifest is a static JSON artifact generated from that catalog. This package consumes the manifest to give you the same typed-event guarantees on the client that you get on the server.

## Install

```bash
npm install @track_relay/client
```

The package ships dual ESM (`dist/index.mjs`) and CommonJS (`dist/index.cjs`) builds plus hand-written TypeScript types (`src/index.d.ts`).

## Usage

The Rails layer owns two pieces of configuration that the JS package needs at boot:

1. **`measurementId`** — your GA4 Measurement ID (`G-XXXXXXXXXX`), sourced from `TrackRelay.config.ga4_measurement_id`.
2. **`manifestUrl`** — the URL of `track_relay_catalog.json`, which Rails writes to `public/` via `rake track_relay:manifest` (auto-run before `assets:precompile` and on every dev reload).

Wire both via an inline ERB script in your layout:

```erb
<%# app/views/layouts/application.html.erb %>
<script type="module">
  import { init } from "@track_relay/client";
  init({
    measurementId: "<%= TrackRelay.config.ga4_measurement_id %>",
    manifestUrl: "<%= asset_path('track_relay_catalog.json') %>"
  });
</script>
```

Then track events anywhere in your JavaScript:

```javascript
import { track } from "@track_relay/client";

document.querySelector("#buy-button").addEventListener("click", () => {
  track("purchase", { value: 9.99, currency: "USD" });
});
```

`track()` validates the params against the manifest entry for `purchase`, then calls `window.gtag("event", "purchase", { value: 9.99, currency: "USD" })`. The first `track()` after `init()` (or after `setClientId()`) emits one `gtag("config", measurementId, { client_id })` so GA4 routes events to the right user.

## API

### `init({ measurementId, manifestUrl, env, onValidationError })`

Initialize the client. Both `measurementId` and `manifestUrl` are **required** — passing nullish or empty-string for either throws synchronously **before** any fetch is attempted, so misconfiguration is loud at the call site.

| Option | Type | Description |
|---|---|---|
| `measurementId` | `string` | GA4 Measurement ID (`G-XXX`). |
| `manifestUrl` | `string` | URL of the typed JSON manifest. |
| `env` | `"development" \| "production"` | Default `"production"`. Dev throws on validation failure; prod warns and drops. |
| `onValidationError` | `(errors: string[]) => void` | Optional hook invoked with validation errors before the throw/warn branch. |

Returns a `Promise<void>` that resolves once the manifest has been fetched and parsed.

### `track(eventName, params)`

Validate `params` against the manifest entry for `eventName` (when one exists) and dispatch via `window.gtag("event", eventName, params)`.

- **Typed event** (in the manifest): params are validated against the typed schema. Missing required keys or wrong types trigger the dev-throw / prod-warn branch (see `env`).
- **Untyped event** (not in the manifest): passes through unchanged. The catalog is opt-in for typing — host apps can adopt event types incrementally.
- **Missing `window.gtag`**: warns and drops the event. Never throws.

### `setClientId(clientId)`

Update the resolved `client_id`. The next `track()` call re-emits `gtag("config", measurementId, { client_id })` so GA4 attributes events to the right user. Pass `null` to clear.

### `Ga4Gtag`

Named export: a server-subscriber-shaped wrapper around `track()` for hosts that prefer object dispatch:

```javascript
import { Ga4Gtag } from "@track_relay/client";
Ga4Gtag.handle("purchase", { value: 9.99, currency: "USD" });
```

Reads the same module-private state that `init({...})` populates — no separate subscriber-side init needed. Mirrors the server-side `TrackRelay::Subscribers::Ga4MeasurementProtocol` shape.

## Validation rules (REQ-05 mirror)

The five manifest types map to JS as follows:

| Manifest type | JS check |
|---|---|
| `integer` | `typeof === "number"` and `Number.isInteger(value)` |
| `float` | `typeof === "number"` and `Number.isFinite(value)` |
| `string` | `typeof === "string"` |
| `boolean` | `typeof === "boolean"` |
| `datetime` | `Date` instance OR ISO8601-parseable string |

Required-param checks fire when the value is `null` or `undefined`. Extra params not declared in `schema.params` are allowed silently (catalog stays opt-in).

## Versioning

`@track_relay/client` ships in lockstep with the `track_relay` gem. The `version` field of the manifest matches the gem version that generated it; consumers can compare against `package.json` `version` to detect drift.

## License

MIT — see [LICENSE.txt](../LICENSE.txt) at the repository root.
