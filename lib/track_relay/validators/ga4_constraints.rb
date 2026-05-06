# frozen_string_literal: true

require "track_relay/errors"

module TrackRelay
  module Validators
    # Enforces Google Analytics 4 naming + sizing constraints on catalog
    # entries. Used by {CatalogValidator} at catalog-load time so
    # GA4-incompatible events fail fast in development rather than silently
    # in production where GA4 would just drop them.
    #
    # Rules implemented (per GA4 docs):
    # - Event names: snake_case, start with a lowercase letter, max 40
    #   chars, not in {TrackRelay::GA4_RESERVED_NAMES}.
    # - Param names: same regex + max 40 chars.
    # - Per-event param count: <= 25 custom params.
    #
    # All violations raise {TrackRelay::Ga4ConstraintError} with a message
    # naming the offender so error messages stay actionable.
    module Ga4Constraints
      # GA4 names must start with a lowercase letter and contain only
      # lowercase letters, digits, and underscores after that.
      NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/

      # GA4 caps custom event/param name length at 40 characters.
      MAX_NAME_LENGTH = 40

      # GA4 caps custom params per event at 25.
      MAX_PARAMS_PER_EVENT = 25

      module_function

      # @param name [Symbol, String] event name to validate
      # @raise [TrackRelay::Ga4ConstraintError] when the name violates any
      #   GA4 rule (shape, length, or reserved-name list)
      # @return [void]
      def validate_event_name!(name)
        as_string = name.to_s

        unless as_string.match?(NAME_PATTERN)
          raise Ga4ConstraintError,
            "Event name #{name.inspect} must be snake_case (matches #{NAME_PATTERN.inspect})"
        end

        if as_string.length > MAX_NAME_LENGTH
          raise Ga4ConstraintError,
            "Event name #{name.inspect} exceeds GA4 max length of #{MAX_NAME_LENGTH} chars (got #{as_string.length})"
        end

        if TrackRelay::GA4_RESERVED_NAMES.include?(as_string)
          raise Ga4ConstraintError,
            "Event name #{name.inspect} is reserved by GA4 (https://support.google.com/analytics/answer/9234069) — pick a non-reserved name"
        end
      end

      # @param params [Hash] params hash from an EventDefinition
      # @raise [TrackRelay::Ga4ConstraintError] when params.size > 25
      # @return [void]
      def validate_param_count!(params)
        if params.size > MAX_PARAMS_PER_EVENT
          raise Ga4ConstraintError,
            "Event has #{params.size} custom params; GA4 caps custom params per event at #{MAX_PARAMS_PER_EVENT}"
        end
      end

      # @param name [Symbol, String] param name to validate
      # @raise [TrackRelay::Ga4ConstraintError] when the param name
      #   violates GA4 shape or length rules
      # @return [void]
      def validate_param_name!(name)
        as_string = name.to_s

        unless as_string.match?(NAME_PATTERN)
          raise Ga4ConstraintError,
            "Param name #{name.inspect} must be snake_case (matches #{NAME_PATTERN.inspect})"
        end

        if as_string.length > MAX_NAME_LENGTH
          raise Ga4ConstraintError,
            "Param name #{name.inspect} exceeds GA4 max length of #{MAX_NAME_LENGTH} chars (got #{as_string.length})"
        end
      end
    end
  end
end
