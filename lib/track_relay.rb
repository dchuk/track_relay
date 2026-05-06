# frozen_string_literal: true

require "track_relay/version"
require "track_relay/errors"

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
end
