# frozen_string_literal: true

require "test_helper"

# Unit coverage for the public `TrackRelay.subscribe(klass_or_instance, only:, except:)`
# registration helper — Plan 02-01.
#
# Contract:
#
# - Accepts a subscriber class (instantiates it via `.new`) OR a
#   pre-built subscriber instance.
# - When `only:` / `except:` are passed, sets them as INSTANCE-level
#   overrides on the registered subscriber. Other instances of the same
#   class — and the class-level defaults declared via `filter` — are
#   NOT mutated.
# - Delegates registration to `TrackRelay.config.subscribe(instance)`.
# - Returns the subscriber instance (so callers can hold a reference).
class TrackRelaySubscribeTest < ActiveSupport::TestCase
  # Plain capture subscriber: synchronous, records names. Used for the
  # class / instance acceptance tests.
  class CaptureSubscriber < TrackRelay::Subscribers::Base
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

  # Subscriber with class-level filter defaults — proves that an
  # `only:` override at registration time does NOT mutate the class.
  class ClassFilteredSubscriber < TrackRelay::Subscribers::Base
    synchronous!
    filter only: %i[purchase]

    def initialize
      super
      @captured = []
    end

    attr_reader :captured

    def deliver(payload)
      @captured << payload.name
    end
  end

  def build_payload(name)
    TrackRelay::EventPayload.untyped(name: name, params: {}, context: {})
  end

  # ---- Acceptance: class vs. instance --------------------------------

  test "TrackRelay.subscribe(klass) instantiates and registers the subscriber" do
    returned = TrackRelay.subscribe(CaptureSubscriber)

    assert_kind_of CaptureSubscriber, returned
    assert_equal [returned], TrackRelay.config.subscribers
  end

  test "TrackRelay.subscribe(instance) accepts a pre-built instance" do
    instance = CaptureSubscriber.new
    returned = TrackRelay.subscribe(instance)

    assert_same instance, returned
    assert_equal [instance], TrackRelay.config.subscribers
  end

  # ---- only:/except: are INSTANCE-level overrides --------------------

  test "TrackRelay.subscribe(klass, only:) sets only_events on the INSTANCE, not the class" do
    sub = TrackRelay.subscribe(CaptureSubscriber, only: %i[purchase])

    # Instance sees the override.
    sub.handle(build_payload(:purchase))
    sub.handle(build_payload(:sign_up))
    assert_equal [:purchase], sub.captured

    # Class default is still untouched (nil — no class-level filter).
    assert_nil CaptureSubscriber.only_events,
      "class-level default should NOT be mutated by a per-instance override"
  end

  test "TrackRelay.subscribe(klass, except:) sets except_events on the INSTANCE, not the class" do
    sub = TrackRelay.subscribe(CaptureSubscriber, except: %i[page_view])

    sub.handle(build_payload(:page_view))
    sub.handle(build_payload(:purchase))
    assert_equal [:purchase], sub.captured

    assert_nil CaptureSubscriber.except_events,
      "class-level default should NOT be mutated by a per-instance override"
  end

  test "per-instance override does not bleed across instances of the same class" do
    a = TrackRelay.subscribe(CaptureSubscriber, only: %i[purchase])
    b = TrackRelay.subscribe(CaptureSubscriber, only: %i[sign_up])

    a.handle(build_payload(:purchase))
    a.handle(build_payload(:sign_up))
    b.handle(build_payload(:purchase))
    b.handle(build_payload(:sign_up))

    assert_equal [:purchase], a.captured
    assert_equal [:sign_up], b.captured
  end

  test "per-instance override replaces (not merges with) class-level default" do
    # Class default is `only: %i[purchase]`. An instance override
    # `only: %i[sign_up]` should make the instance receive ONLY
    # `:sign_up` — the class default is replaced, not unioned.
    sub = TrackRelay.subscribe(ClassFilteredSubscriber, only: %i[sign_up])

    sub.handle(build_payload(:purchase))
    sub.handle(build_payload(:sign_up))

    assert_equal [:sign_up], sub.captured
    # Class-level default unchanged for any other instance:
    plain = ClassFilteredSubscriber.new
    plain.handle(build_payload(:purchase))
    plain.handle(build_payload(:sign_up))
    assert_equal [:purchase], plain.captured,
      "an instance WITHOUT the override still sees the class-level default"
  end

  # ---- No filter override = inherits class default -------------------

  test "TrackRelay.subscribe(klass) without only:/except: leaves the class-level default intact" do
    sub = TrackRelay.subscribe(ClassFilteredSubscriber)

    sub.handle(build_payload(:purchase))
    sub.handle(build_payload(:sign_up))

    assert_equal [:purchase], sub.captured,
      "no-override registration falls through to the class-level default"
  end
end
