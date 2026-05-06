# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"

module TrackRelay
  # Per-request / per-job ambient context for track_relay.
  #
  # Subclasses {ActiveSupport::CurrentAttributes} so the host application
  # (or this gem's controller/job middleware) can stash request-scoped
  # values that {TrackRelay.track} reads back at event time without
  # threading them through every call site.
  #
  # All attributes are auto-reset between requests, jobs, and (in the
  # test suite) between tests via
  # `ActiveSupport::CurrentAttributes::TestHelper`, which is mixed into
  # `ActiveSupport::TestCase` in `test/test_helper.rb`.
  #
  # @example Setting context in a controller before-filter
  #   before_action do
  #     TrackRelay::Current.user = current_user
  #     TrackRelay::Current.request = request
  #     TrackRelay::Current.controller = self
  #   end
  #
  # @example Block-scoped override (e.g. impersonation, replay)
  #   TrackRelay::Current.set(user: other_user) do
  #     TrackRelay.track(:article_viewed, article_id: 42)
  #   end
  class Current < ActiveSupport::CurrentAttributes
    attribute :user, :request, :visit, :controller, :client_id
  end
end
