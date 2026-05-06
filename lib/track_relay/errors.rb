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
end
