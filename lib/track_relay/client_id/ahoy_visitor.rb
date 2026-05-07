# frozen_string_literal: true

module TrackRelay
  module ClientId
    # Resolver that returns the current Ahoy visitor token, when the
    # host application has the [ahoy](https://github.com/ankane/ahoy)
    # gem installed AND the controller exposes its `ahoy` helper.
    #
    # Default position-1 entry in {Configuration#client_id_resolvers}
    # — between {Ga} (cookie-based) and {Session} (UUID fallback).
    #
    # ## Duck-typed integration
    #
    # This resolver does NOT `require "ahoy"`. It probes the controller
    # via `respond_to?(:ahoy, true)` so the gem boots cleanly in apps
    # without Ahoy. When Ahoy is absent, `#call` returns `nil` and the
    # next resolver in the chain takes over.
    #
    # When Ahoy IS present, it exposes `controller.ahoy.current_visit`
    # — an `Ahoy::Visit` ActiveRecord model with a `visitor_token`
    # string column. We read that public API only; nothing internal.
    class AhoyVisitor
      # @param controller [Object] any controller-like object that may
      #   or may not include `Ahoy::Trackable`.
      # @return [String, nil] `ahoy.current_visit.visitor_token` if
      #   available, else `nil`.
      def call(controller:, **)
        return nil unless controller&.respond_to?(:ahoy, true)

        controller.ahoy&.current_visit&.visitor_token
      end
    end
  end
end
