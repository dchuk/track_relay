# frozen_string_literal: true

require "minitest/autorun"
require "track_relay"
require "track_relay/event_payload"

class EventPayloadTest < Minitest::Test
  ParamSchema = TrackRelay::EventDefinition::ParamSchema

  def build_definition(params = {})
    schemas = params.each_with_object({}) do |(key, opts), acc|
      acc[key] = ParamSchema.new(name: key, **opts)
    end
    TrackRelay::EventDefinition.new(name: :sample_event, params: schemas)
  end

  # ---- Required ----

  def test_missing_required_param_raises_validation_error_naming_the_key
    definition = build_definition(article_id: {type: :integer, required: true})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {})

    error = assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
    assert_match(/article_id/, error.message)
    assert_match(/required/i, error.message)
  end

  def test_missing_optional_param_does_not_raise
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {})

    payload.validate! # should not raise
  end

  # ---- Integer coercion ----

  def test_integer_coercion_from_string
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {article_id: "42"})

    payload.validate!

    assert_equal 42, payload.params[:article_id]
  end

  def test_integer_coercion_from_integer_passes_through
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {article_id: 7})

    payload.validate!

    assert_equal 7, payload.params[:article_id]
  end

  def test_integer_bad_string_raises_validation_error
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {article_id: "not-a-number"})

    assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
  end

  # ---- String coercion + max-length ----

  def test_string_coercion_from_symbol
    definition = build_definition(name: {type: :string})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {name: :foo})

    payload.validate!

    assert_equal "foo", payload.params[:name]
  end

  def test_string_max_length_overflow_raises_no_silent_truncation
    definition = build_definition(slug: {type: :string, max: 10})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {slug: "this-is-far-too-long"})

    error = assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
    assert_match(/slug/, error.message)
    assert_match(/(max|10)/i, error.message)
  end

  def test_string_under_max_length_passes
    definition = build_definition(slug: {type: :string, max: 10})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {slug: "ok"})

    payload.validate!

    assert_equal "ok", payload.params[:slug]
  end

  # ---- Sanitize-before-validate ----

  def test_sanitize_runs_before_max_check
    sanitize = ->(v) { v.to_s[0, 10] }
    definition = build_definition(slug: {type: :string, max: 10, sanitize: sanitize})
    payload = TrackRelay::EventPayload.new(
      definition: definition,
      params: {slug: "this-is-far-too-long-200-chars-long"}
    )

    payload.validate!

    assert_equal 10, payload.params[:slug].length
    assert_equal "this-is-fa", payload.params[:slug]
  end

  def test_sanitize_runs_before_format_check
    sanitize = ->(v) { v.to_s.downcase }
    definition = build_definition(tier: {type: :string, format: /\A[a-z]+\z/, sanitize: sanitize})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {tier: "PRO"})

    payload.validate!

    assert_equal "pro", payload.params[:tier]
  end

  # ---- Inclusion list (in:) ----

  def test_in_inclusion_list_match_passes
    definition = build_definition(tier: {type: :string, in: %w[free pro enterprise]})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {tier: "pro"})

    payload.validate!

    assert_equal "pro", payload.params[:tier]
  end

  def test_in_inclusion_list_mismatch_raises
    definition = build_definition(tier: {type: :string, in: %w[free pro enterprise]})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {tier: "ultra"})

    error = assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
    assert_match(/tier/, error.message)
    assert_match(/(ultra|inclusion|in)/i, error.message)
  end

  # ---- Format (regex) ----

  def test_format_match_passes
    definition = build_definition(slug: {type: :string, format: /\A[a-z-]+\z/})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {slug: "good-slug"})

    payload.validate!

    assert_equal "good-slug", payload.params[:slug]
  end

  def test_format_mismatch_raises
    definition = build_definition(slug: {type: :string, format: /\A[a-z-]+\z/})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {slug: "BAD_SLUG"})

    error = assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
    assert_match(/slug/, error.message)
    assert_match(/format/i, error.message)
  end

  # ---- Float ----

  def test_float_coercion_from_string
    definition = build_definition(price: {type: :float})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {price: "9.99"})

    payload.validate!

    assert_in_delta 9.99, payload.params[:price]
  end

  def test_float_bad_string_raises
    definition = build_definition(price: {type: :float})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {price: "abc"})

    assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
  end

  # ---- Boolean strict ----

  def test_boolean_true_literal_passes
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: true})

    payload.validate!

    assert_equal true, payload.params[:flag]
  end

  def test_boolean_false_literal_passes
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: false})

    payload.validate!

    assert_equal false, payload.params[:flag]
  end

  def test_boolean_string_true_coerces_to_true
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: "true"})

    payload.validate!

    assert_equal true, payload.params[:flag]
  end

  def test_boolean_string_false_coerces_to_false
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: "false"})

    payload.validate!

    assert_equal false, payload.params[:flag]
  end

  def test_boolean_one_coerces_to_true
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: 1})

    payload.validate!

    assert_equal true, payload.params[:flag]
  end

  def test_boolean_zero_coerces_to_false
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: 0})

    payload.validate!

    assert_equal false, payload.params[:flag]
  end

  def test_boolean_other_string_raises
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: "yes"})

    assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
  end

  def test_boolean_arbitrary_object_raises
    definition = build_definition(flag: {type: :boolean})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {flag: [1, 2]})

    assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
  end

  # ---- Datetime ----

  def test_datetime_iso8601_string_coerces_to_time
    definition = build_definition(at: {type: :datetime})
    payload = TrackRelay::EventPayload.new(
      definition: definition,
      params: {at: "2026-05-06T12:34:56Z"}
    )

    payload.validate!

    assert_kind_of Time, payload.params[:at]
    assert_equal 2026, payload.params[:at].year
  end

  def test_datetime_time_passes_through
    now = Time.now
    definition = build_definition(at: {type: :datetime})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {at: now})

    payload.validate!

    assert_equal now, payload.params[:at]
  end

  def test_datetime_bad_string_raises
    definition = build_definition(at: {type: :datetime})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {at: "not-a-date"})

    assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
  end

  def test_datetime_arbitrary_object_raises
    definition = build_definition(at: {type: :datetime})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {at: [2026, 5, 6]})

    assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
  end

  # ---- Extras ----

  def test_extra_param_not_in_schema_raises
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(
      definition: definition,
      params: {article_id: 1, surprise: "boom"}
    )

    error = assert_raises(TrackRelay::ValidationError) do
      payload.validate!
    end
    assert_match(/surprise/, error.message)
  end

  # ---- Untyped variant ----

  def test_untyped_payload_skips_validation
    payload = TrackRelay::EventPayload.untyped(name: :anything, params: {whatever: "raw"})

    payload.validate! # should not raise

    assert_equal({whatever: "raw"}, payload.params)
  end

  def test_untyped_payload_to_h_uses_stored_name
    payload = TrackRelay::EventPayload.untyped(name: :random_event, params: {a: 1})

    hash = payload.to_h

    assert_equal :random_event, hash[:name]
    assert_equal({a: 1}, hash[:params])
  end

  def test_untyped_payload_name_method_returns_stored_name
    payload = TrackRelay::EventPayload.untyped(name: :foo, params: {})

    assert_equal :foo, payload.name
  end

  # ---- name + to_h ----

  def test_typed_name_returns_definition_name
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {article_id: 1})

    assert_equal :sample_event, payload.name
  end

  def test_to_h_returns_iso8601_timestamp
    definition = build_definition(article_id: {type: :integer})
    fixed_time = Time.utc(2026, 5, 6, 12, 0, 0)
    payload = TrackRelay::EventPayload.new(
      definition: definition,
      params: {article_id: 1},
      timestamp: fixed_time
    )
    payload.validate!

    hash = payload.to_h

    assert_equal :sample_event, hash[:name]
    assert_equal({article_id: 1}, hash[:params])
    assert_equal "2026-05-06T12:00:00Z", hash[:timestamp]
  end

  def test_to_h_includes_context
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(
      definition: definition,
      params: {article_id: 1},
      context: {user_id: 42, visitor_token: "abc"}
    )
    payload.validate!

    hash = payload.to_h

    assert_equal({user_id: 42, visitor_token: "abc"}, hash[:context])
  end

  # ---- definition + accessors ----

  def test_payload_exposes_definition
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {})

    assert_same definition, payload.definition
  end

  def test_validate_returns_coerced_params_hash
    definition = build_definition(article_id: {type: :integer})
    payload = TrackRelay::EventPayload.new(definition: definition, params: {article_id: "5"})

    coerced = payload.validate!

    assert_equal({article_id: 5}, coerced)
  end
end
