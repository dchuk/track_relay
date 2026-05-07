# frozen_string_literal: true

require "test_helper"

# Unit coverage for the subscriber-side `only:` / `except:` event-name
# filter on {TrackRelay::Subscribers::Base} — Plan 02-01.
#
# Contract under test:
#
# - `filter only: %i[purchase]` ⇒ only events whose `payload.name == :purchase`
#   are delivered; all others short-circuit at the top of `#handle`.
# - `filter except: %i[page_view]` ⇒ all events EXCEPT `:page_view` are
#   delivered.
# - No filter set ⇒ every event is delivered (Phase 1 behavior preserved).
# - The filter check runs BEFORE `safe_deliver`'s rescue boundary, so a
#   subscriber whose `#deliver` would raise does NOT log when the event
#   is filtered out (the filtered branch never enters `safe_deliver`).
class SubscribersBaseFilterTest < ActiveSupport::TestCase
  # Tiny in-memory capture subscriber: synchronous, records every
  # payload that makes it through the filter gate. One subclass per
  # test so `class_attribute` settings (`only_events` / `except_events`)
  # do not leak between tests.
  class CapturingBase < TrackRelay::Subscribers::Base
    synchronous!

    def initialize
      super
      @captured = []
    end

    attr_reader :captured

    def deliver(payload)
      @captured << payload.name
    end
  end

  # A buggy synchronous subscriber whose `#deliver` always raises. Used
  # to prove the filter gate runs BEFORE `safe_deliver` (a filtered
  # event must NOT trigger the rescue+log path).
  class BoomBase < TrackRelay::Subscribers::Base
    synchronous!

    def deliver(_payload)
      raise "should not be reached when filtered"
    end
  end

  setup do
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
  end

  teardown do
    Rails.logger = @prior_logger
  end

  def build_payload(name)
    TrackRelay::EventPayload.untyped(name: name, params: {}, context: {})
  end

  # ---- only: ---------------------------------------------------------

  test "filter only: %i[purchase] receives :purchase but drops :sign_up" do
    klass = Class.new(CapturingBase) { filter only: %i[purchase] }
    sub = klass.new

    sub.handle(build_payload(:purchase))
    sub.handle(build_payload(:sign_up))

    assert_equal [:purchase], sub.captured
  end

  # ---- except: -------------------------------------------------------

  test "filter except: %i[page_view] drops :page_view but receives others" do
    klass = Class.new(CapturingBase) { filter except: %i[page_view] }
    sub = klass.new

    sub.handle(build_payload(:page_view))
    sub.handle(build_payload(:purchase))
    sub.handle(build_payload(:sign_up))

    assert_equal %i[purchase sign_up], sub.captured
  end

  # ---- no filter -----------------------------------------------------

  test "no filter set: receives every event (Phase 1 behavior preserved)" do
    sub = CapturingBase.new

    sub.handle(build_payload(:a))
    sub.handle(build_payload(:b))
    sub.handle(build_payload(:c))

    assert_equal %i[a b c], sub.captured
  end

  # ---- ordering: filter runs BEFORE safe_deliver ---------------------

  test "filter check runs BEFORE safe_deliver: filtered event with raising deliver does not log" do
    # If `filtered?` ran INSIDE `safe_deliver`, the rescue would swallow
    # the error and Rails.logger.error would emit. The contract is the
    # opposite: the filter gate is at the TOP of `#handle`, so a
    # filtered event short-circuits and never enters `safe_deliver`.
    klass = Class.new(BoomBase) { filter only: %i[purchase] }
    sub = klass.new

    result = sub.handle(build_payload(:sign_up))

    assert_nil result, "filtered handle returns nil"
    refute_match(/track_relay/, @log_io.string,
      "filtered event should not log — it never reached safe_deliver")
  end

  test "filter does not block matching events: a buggy deliver still raises through safe_deliver" do
    # Companion to the previous test: prove the filter is the ONLY thing
    # short-circuiting. When the event matches `only:`, the buggy
    # `#deliver` runs, `safe_deliver` rescues and logs.
    klass = Class.new(BoomBase) { filter only: %i[purchase] }
    sub = klass.new

    result = sub.handle(build_payload(:purchase))

    assert_kind_of StandardError, result, "matching event reaches safe_deliver"
    assert_match(/\[track_relay\] subscriber=/, @log_io.string)
  end
end
