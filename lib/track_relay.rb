# frozen_string_literal: true

require "track_relay/version"
require "track_relay/errors"
require "track_relay/event_definition"
require "track_relay/validators/ga4_constraints"
require "track_relay/validators/catalog_validator"
require "track_relay/catalog"
require "track_relay/dsl/param_builder"
require "track_relay/dsl/event_builder"
require "track_relay/current"
require "track_relay/configuration"
require "track_relay/instrumenter"
require "track_relay/subscribers/base"
require "track_relay/subscribers/test"
require "track_relay/subscribers/logger"
require "track_relay/delivery_job"
require "track_relay/dispatcher"
require "track_relay/controller_tracking"

# The Railtie is the only Rails-coupled file pulled in at load time.
# Load it conditionally so the gem still works in non-Rails contexts
# (plain `require "track_relay"` from a script). Everything above this
# line depends on activesupport but not the full Rails stack.
require "track_relay/railtie" if defined?(Rails::Railtie)

module TrackRelay
  # Param keys that cannot appear in a catalog event because they collide
  # with the runtime context that track_relay injects automatically
  # (TrackRelay::Current + reserved-key extraction in `track`).
  #
  # If a catalog event declares any of these as params, the catalog
  # validator raises {ReservedKeyError} at load time so the conflict
  # surfaces during boot rather than at track time.
  RESERVED_KEYS = %i[user visitor_token client_id request].freeze

  # Event names Google Analytics 4 reserves for its own use. Custom events
  # in the catalog must not use any of these names — GA4 silently drops
  # them on ingestion. Source:
  # https://support.google.com/analytics/answer/9234069
  #
  # Kept here as a frozen Array of Strings so {GA4_RESERVED_NAMES.include?}
  # works against both String and Symbol input via to_s coercion in the
  # validator.
  GA4_RESERVED_NAMES = %w[
    ad_click
    ad_exposure
    ad_query
    ad_reward
    adunit_exposure
    app_clear_data
    app_exception
    app_install
    app_remove
    app_store_refund
    app_store_subscription_cancel
    app_store_subscription_convert
    app_store_subscription_renew
    app_update
    click
    error
    file_download
    first_open
    first_visit
    form_start
    form_submit
    in_app_purchase
    notification_dismiss
    notification_foreground
    notification_open
    notification_receive
    os_update
    page_view
    screen_view
    scroll
    session_start
    session_start_with_rollout
    session_resume_with_rollout
    user_engagement
    video_complete
    video_progress
    video_start
    view_search_results
  ].freeze

  class << self
    # Process-wide {Configuration} singleton. Lazily instantiated on
    # first access. Reset between tests via {reset_config!}.
    #
    # @return [Configuration]
    def config
      @config ||= Configuration.new
    end

    # Yield the {Configuration} singleton for host-app setup, then
    # return it so callers can chain.
    #
    #   TrackRelay.configure do |c|
    #     c.subscribe(MySubscriber.new)
    #     c.untyped_events_allowed = false
    #   end
    #
    # @yieldparam config [Configuration]
    # @return [Configuration]
    def configure
      yield(config)
      config
    end

    # Replace the singleton with a fresh {Configuration}. Used by the
    # test suite's teardown hook so per-test mutations do not leak.
    #
    # @return [Configuration] the new (default) configuration
    def reset_config!
      @config = Configuration.new
    end
  end

  # Track an event — typed (catalog-defined) or untyped.
  #
  # Reserved keys (`:user`, `:request`, `:client_id`, `:visitor_token`)
  # are partitioned out of `params` BEFORE catalog lookup so they never
  # appear in `payload.params`. `:user`/`:request`/`:client_id` are
  # bound on {Current} for the duration of the call;
  # `:visitor_token` is merged directly into `payload.context`.
  #
  # See {Instrumenter.track} for full semantics.
  #
  # @param name [Symbol]
  # @param params [Hash]
  # @return [void]
  def self.track(name, **params)
    Instrumenter.track(name, **params)
  end

  # Identify a user — Phase 01 thin pass-through.
  #
  # See {Instrumenter.identify}.
  #
  # @param user [Object]
  # @param user_properties [Hash]
  # @return [void]
  def self.identify(user, **user_properties)
    Instrumenter.identify(user, **user_properties)
  end

  # Top-level entry point for the catalog DSL.
  #
  # Evaluates `block` against a {DSL::EventBuilder} so callers can use
  # `event :name do ... end` and `user_property :name, :type` directly:
  #
  #   TrackRelay.catalog do
  #     event :article_viewed do
  #       integer :article_id, required: true
  #     end
  #
  #     user_property :plan, :string
  #   end
  #
  # Each `event` declaration validates against GA4 + reserved-key rules
  # and registers the resulting {EventDefinition} in {Catalog} before
  # returning. Failures raise {Ga4ConstraintError},
  # {ReservedKeyError}, or {CatalogError} depending on the violation.
  def self.catalog(&block)
    DSL::EventBuilder.new.instance_exec(&block)
  end
end
