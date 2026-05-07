# Upgrading track_relay

This document summarizes breaking changes between `track_relay` releases
and how to migrate. For the full release history, see
[CHANGELOG.md](CHANGELOG.md).

## 0.1.0 → 0.2.0

No breaking changes to the Ruby gem surface. New features added:

- `TrackRelay::Subscribers::Ga4MeasurementProtocol` — wire with
  `config.ga4_measurement_id` and `config.ga4_api_secret`.
- `config.client_id_resolvers` — ordered chain (GA cookie, Ahoy
  visitor, session fallback). Default chain preserves existing
  `_ga` cookie behavior.
- Subscriber-side `only:` / `except:` filters added to
  `TrackRelay.subscribe(klass, only:, except:)`.
- New rake task: `track_relay:lint:ga4` — audits your catalog
  against GA4 constraints (snake_case, max 40 chars per event name,
  max 25 custom params per event, reserved-name refusal).

No host-app code changes are required. Optional adoption:
`bundle exec rake track_relay:lint:ga4` and add the GA4 subscriber if
you use Google Analytics.

## 0.2.0 → 0.3.0

**One BREAKING change (JavaScript client only). Ruby gem surface is
unaffected.**

### BREAKING: `init({ manifestUrl })` no longer requires `measurementId`

In `@track_relay/client`, the `init({ manifestUrl })` call no longer
requires a `measurementId` parameter. If your code relied on the
missing-`measurementId` throw to detect misconfiguration, add an
explicit assertion before calling `init`:

```javascript
import { init } from "@track_relay/client";

const measurementId = process.env.GA4_MEASUREMENT_ID;
if (!measurementId) {
  throw new Error("GA4_MEASUREMENT_ID is required");
}

init({ manifestUrl: "/track_relay_catalog.json", measurementId });
```

### New features in 0.3.0

- `TrackRelay::Subscribers::Ahoy` — server-side subscriber that uses
  only the public Ahoy API (`controller.ahoy.track` /
  `current_visit.track`). Wire with
  `config.subscribe TrackRelay::Subscribers::Ahoy.new` (requires the
  `ahoy_matey` gem).
- `AhoyJs` export added in `@track_relay/client` — wraps
  `window.ahoy.track` using the same event names as the server.

## 0.3.0 → 1.0.0

**No breaking changes.** 1.0.0 adds:

- Three Rails generators: `track_relay:install`, `track_relay:event`,
  `track_relay:subscriber`. Run
  `bin/rails generate track_relay:install` in your existing app —
  the inject step is idempotent and skips if
  `include TrackRelay::ControllerTracking` is already present.
- Public-API stability guarantee. See [README.md](README.md#public-api-stability)
  for the stable surface; classes outside that list (`EventPayload`,
  `Instrumenter`, `Dispatcher`, `Catalog`, `Current`, `DeliveryJob`,
  `ClientId::*`) are internal and may change without a major bump.
- E2E test coverage proving the install generator's output works
  end-to-end through a real controller call.
- Documentation: getting-started guide at [USAGE.md](USAGE.md).

To upgrade:

1. Bump your Gemfile pin to `gem "track_relay", "~> 1.0"`.
2. `bundle update track_relay`.
3. (Optional but recommended) Run
   `bin/rails generate track_relay:install` to refresh your initializer
   with the latest comments and ApplicationSubscriber base class.
   Existing files will trigger a Thor "overwrite?" prompt; the inject
   step is idempotent regardless.
4. `bundle exec rake test` — should pass without further changes.
