# frozen_string_literal: true

require "active_support/concern"

module TrackRelay
  # Job-side tracking helper.
  #
  # Host applications include this concern in `ApplicationJob` (or any
  # job) to expose a `track(name, **params)` instance method that
  # delegates to {TrackRelay.track}.
  #
  # Unlike {ControllerTracking}, this concern is intentionally minimal
  # — it does NOT auto-populate {Current}. The reason is the Rails
  # Executor: ActiveJob wraps every `perform` with the Executor, which
  # calls `ActiveSupport::CurrentAttributes.clear_all` BEFORE the job
  # runs. So any `Current.user` set in the request that enqueued the
  # job is gone by the time `perform` runs — even under the inline /
  # test queue adapter. Auto-populating from constructor args would be
  # wrong: the args are serialized through the queue, but the in-memory
  # context (visit, request, etc.) is not.
  #
  # Job authors are responsible for restoring whatever context they
  # care about. The documented pattern is `Current.set(user: u, ...)
  # { track :foo, ... }`. The block form binds attributes for the
  # duration of the block, then unwinds — perfect for a single `track`
  # call inside `perform`.
  #
  # @example Documented usage
  #   class WelcomeEmailJob < ApplicationJob
  #     include TrackRelay::JobTracking
  #
  #     def perform(user)
  #       TrackRelay::Current.set(user: user, visitor_token: user.last_visitor_token) do
  #         track :welcome_email_sent, template: "v3"
  #       end
  #     end
  #   end
  module JobTracking
    extend ActiveSupport::Concern

    # Delegate to {TrackRelay.track}. Sugar for in-job call sites.
    #
    # @param name [Symbol]
    # @param params [Hash]
    # @return [void]
    def track(name, **params)
      TrackRelay.track(name, **params)
    end
  end
end
