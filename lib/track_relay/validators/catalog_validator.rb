# frozen_string_literal: true

require "track_relay/errors"
require "track_relay/validators/ga4_constraints"

module TrackRelay
  module Validators
    # Validates an {EventDefinition} at catalog-load time.
    #
    # Runs both GA4 constraint checks ({Ga4Constraints}) and the
    # reserved-key collision guard. Failures raise immediately so the
    # offending catalog file fails to load — much louder than a silent
    # collision at track time.
    #
    # Two distinct error types are raised by design:
    # - {ReservedKeyError} for params that collide with the runtime
    #   context keys ({TrackRelay::RESERVED_KEYS}).
    # - {Ga4ConstraintError} for any GA4 rule violation.
    #
    # This module is invoked by `EventBuilder#event` (DSL) before
    # registering the definition with the catalog. It is also safe to call
    # against externally-built definitions (e.g. tests).
    module CatalogValidator
      module_function

      # Run all catalog-load-time checks against a definition.
      #
      # @param definition [TrackRelay::EventDefinition]
      # @raise [TrackRelay::ReservedKeyError] when a param key collides
      #   with a reserved context key
      # @raise [TrackRelay::Ga4ConstraintError] when any GA4 rule fails
      # @return [void]
      def validate!(definition)
        Ga4Constraints.validate_event_name!(definition.name)
        Ga4Constraints.validate_param_count!(definition.params)

        definition.params.each_key do |param_name|
          if TrackRelay::RESERVED_KEYS.include?(param_name)
            raise ReservedKeyError,
              "Param #{param_name.inspect} on event #{definition.name.inspect} collides with a reserved context key — rename to e.g. :actor_user_id, :session_token, :tracking_client_id, or :http_request"
          end

          Ga4Constraints.validate_param_name!(param_name)
        end
      end
    end
  end
end
