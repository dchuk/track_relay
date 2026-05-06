# frozen_string_literal: true

require "minitest/autorun"
require "track_relay/event_definition"

class EventDefinitionTest < Minitest::Test
  ParamSchema = TrackRelay::EventDefinition::ParamSchema

  def test_new_definition_with_only_a_name_has_empty_params_and_user_properties
    definition = TrackRelay::EventDefinition.new(name: :article_viewed)

    assert_equal :article_viewed, definition.name
    assert_equal({}, definition.params)
    assert_equal({}, definition.user_properties)
  end

  def test_definition_with_one_param_schema_exposes_it_by_key
    schema = ParamSchema.new(
      name: :article_id,
      type: :integer,
      required: true,
      max: nil,
      in: nil,
      format: nil,
      sanitize: nil
    )
    definition = TrackRelay::EventDefinition.new(
      name: :article_viewed,
      params: {article_id: schema}
    )

    assert_same schema, definition.params[:article_id]
    assert_equal :integer, definition.params[:article_id].type
    assert_equal true, definition.params[:article_id].required
  end

  def test_definition_is_frozen_so_params_hash_cannot_be_mutated
    definition = TrackRelay::EventDefinition.new(name: :foo)

    assert_predicate definition, :frozen?
    assert_predicate definition.params, :frozen?
    assert_predicate definition.user_properties, :frozen?

    assert_raises(FrozenError) do
      definition.params[:added_later] = :nope
    end
  end

  def test_param_schema_provides_defaults_for_required_max_in_format_sanitize
    schema = ParamSchema.new(name: :foo, type: :string)

    assert_equal :foo, schema.name
    assert_equal :string, schema.type
    assert_equal false, schema.required
    assert_nil schema.max
    assert_nil schema.in
    assert_nil schema.format
    assert_nil schema.sanitize
  end

  def test_param_schema_accepts_all_six_validator_slots
    sanitize = ->(v) { v.to_s.strip }
    schema = ParamSchema.new(
      name: :tier,
      type: :string,
      required: true,
      max: 20,
      in: %w[free pro enterprise],
      format: /\A[a-z]+\z/,
      sanitize: sanitize
    )

    assert_equal :tier, schema.name
    assert_equal :string, schema.type
    assert_equal true, schema.required
    assert_equal 20, schema.max
    assert_equal %w[free pro enterprise], schema.in
    assert_equal(/\A[a-z]+\z/, schema.format)
    assert_same sanitize, schema.sanitize
  end

  def test_user_properties_are_exposed_via_attr_reader
    definition = TrackRelay::EventDefinition.new(
      name: :foo,
      user_properties: {plan: :string}
    )

    assert_equal({plan: :string}, definition.user_properties)
  end
end
