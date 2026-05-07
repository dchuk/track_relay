# frozen_string_literal: true

require "securerandom"

module TrackRelay
  module ClientId
    # Last-resort resolver that mints a session-stable UUID when no
    # other resolver in the chain produced a client_id.
    #
    # Default position-2 (final) entry in
    # {Configuration#client_id_resolvers}. Stores the generated UUID at
    # `session[:track_relay_client_id]` so subsequent requests on the
    # same Rails session reuse the same value — every visitor gets a
    # consistent client_id even if they have no `_ga` cookie and no
    # Ahoy visit record.
    #
    # ## Storage
    #
    # Uses the host app's standard session store (cookie store, Redis,
    # ActiveRecord, etc.) — whatever `controller.session` provides.
    # The value is a plain UUID string; no signing or encryption is
    # required (it has no security implications).
    #
    # ## Sessionless contexts
    #
    # API-only controllers without session middleware (and any
    # controller-less context) have `controller.session == nil`. The
    # resolver returns `nil` in that case and the chain falls through
    # to whatever follows — or to `nil` overall, leaving
    # {Current.client_id} unset (the same outcome as Phase 01).
    class Session
      SESSION_KEY = :track_relay_client_id

      # @param controller [#session] any controller-like object with a
      #   Rails-style session hash.
      # @return [String, nil] a stable UUID, or `nil` when no session
      #   is available.
      def call(controller:, **)
        session = controller&.session
        return nil unless session

        session[SESSION_KEY] ||= SecureRandom.uuid
      end
    end
  end
end
