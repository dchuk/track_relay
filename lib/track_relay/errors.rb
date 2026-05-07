# frozen_string_literal: true

module TrackRelay
  # Base class for every error track_relay raises.
  #
  # Consumers can rescue `TrackRelay::Error` to catch any failure originating
  # from the gem (validation, catalog load-time checks, GA4 constraint
  # violations, unknown events, etc.) without depending on individual
  # subclasses.
  class Error < StandardError; end

  # Raised at catalog-load time when an event declares a param whose name
  # collides with one of the reserved context keys (see {RESERVED_KEYS}).
  class ReservedKeyError < Error; end

  # Raised at catalog-load time when an event or param violates a Google
  # Analytics 4 constraint (reserved event name, illegal characters,
  # length, or > 25 custom params per event).
  class Ga4ConstraintError < Error; end

  # Raised at track time when an EventPayload's params do not satisfy the
  # corresponding EventDefinition (missing required key, failed coercion,
  # max-length overflow, inclusion-list miss, format mismatch, or undeclared
  # extra param).
  class ValidationError < Error; end

  # Raised at catalog-load time on registry-level problems such as
  # double-registering the same event name.
  class CatalogError < Error; end

  # Raised when callers attempt to track an event that is not present in
  # the catalog and untyped events are disabled.
  class UnknownEventError < Error; end

  # Raised by a subscriber's `#deliver` to signal a *transient* failure
  # that the {DeliveryJob} should retry via ActiveJob's `retry_on`.
  # Examples: HTTP 5xx response, `Net::OpenTimeout`, `Errno::ECONNREFUSED`,
  # `SocketError` against the GA4 Measurement Protocol endpoint.
  #
  # Inherits from `StandardError` (not {Error}) so the
  # {Subscribers::Base#safe_deliver} carve-out can re-raise it without
  # dragging in unrelated track_relay error semantics — and so consumers
  # who rescue `TrackRelay::Error` to log validation failures do not
  # accidentally swallow a retriable network blip.
  class DeliveryRetriableError < StandardError; end

  # Raised by a subscriber's `#deliver` to signal a *permanent* failure
  # that the {DeliveryJob} should drop via ActiveJob's `discard_on`
  # (HTTP 4xx, malformed credentials, etc.). Defensive: GA4 returns 2xx
  # in practice even on bad payloads, but we map 4xx defensively in case
  # Google ever changes that contract. Same `StandardError` rationale as
  # {DeliveryRetriableError}.
  class DeliveryDiscardableError < StandardError; end
end
