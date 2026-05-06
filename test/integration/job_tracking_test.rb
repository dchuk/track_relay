# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Integration coverage for {TrackRelay::JobTracking}.
#
# `JobTracking` is intentionally minimal: it exposes a `track`
# instance method (sugar for {TrackRelay.track}) but does NOT
# auto-populate {Current}. ActiveJob wraps every `perform` with a
# Rails Executor which calls `CurrentAttributes.clear_all` BEFORE the
# job runs (see RESEARCH.md §5), so any `Current.user` set in the
# request that enqueued the job is gone by the time `perform` runs —
# even under the inline / test queue adapter.
#
# Job authors are responsible for restoring the context they care
# about. The documented pattern is `Current.set(user: u, ...) { track
# :foo, ... }`. The block form binds attributes for the duration of
# the block, then unwinds — perfect for a single `track` call inside
# `perform`.
#
# These tests pin both halves of that contract:
#
#   1. Happy path: `Current.set(user: u) { track ... }` produces
#      `payload.context[:user] == u`.
#   2. Reserved-key extraction: `track :foo, visitor_token: "vt"` lands
#      in `payload.context[:visitor_token]` (Instrumenter's
#      DIRECT_CONTEXT_KEYS path).
#   3. Executor reset gotcha: a job that does NOT call `Current.set`
#      sees `Current.user == nil` even when the test set it
#      synchronously before `perform_enqueued_jobs`.
class JobTrackingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    TrackRelay.catalog do
      event :welcome_email_sent do
        integer :user_id, required: true
        string :template, required: true
      end
    end
  end

  test "track helper inside a job fires an event with Current populated via Current.set block" do
    captured = nil
    sub = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, payload|
      captured = payload[:event]
    end

    perform_enqueued_jobs do
      WelcomeEmailJob.perform_later(7, "vt-abc")
    end

    refute_nil captured
    assert_equal :welcome_email_sent, captured.name
    assert_equal 7, captured.params[:user_id]
    assert_equal "v3", captured.params[:template]
    # Reserved-key extraction: :visitor_token bypasses Current and
    # lands directly in payload.context.
    assert_equal "vt-abc", captured.context[:visitor_token]
    # Current.set(user: user) block populates Current.user for the
    # duration of the track call, so the snapshot captures it.
    refute_nil captured.context[:user],
      "Current.user should be populated via Current.set block"
    assert_equal 7, captured.context[:user].id
  ensure
    ActiveSupport::Notifications.unsubscribe(sub) if sub
  end

  test "Executor resets Current before job perform (no Current.set means nil user)" do
    # Set Current outside the job; the Rails Executor that wraps
    # perform calls CurrentAttributes.clear_all before invoking the
    # job, so the value should be gone by the time `perform` runs.
    TrackRelay::Current.user = "request_user"

    saw_user_at_track = :sentinel
    sub = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, payload|
      saw_user_at_track = payload[:event].context[:user]
    end

    job_class = Class.new(ActiveJob::Base) do
      include TrackRelay::JobTracking

      def perform
        # No Current.set — observe Current.user is nil at instrument
        # time despite the request having set it.
        track :welcome_email_sent, user_id: 1, template: "vX"
      end
    end
    self.class.const_set(:TempProbeJob, job_class)

    begin
      perform_enqueued_jobs do
        TempProbeJob.perform_later
      end
      assert_nil saw_user_at_track,
        "Executor should reset Current.user before job perform"
    ensure
      self.class.send(:remove_const, :TempProbeJob)
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end
  end
end
