# frozen_string_literal: true

require "minitest/autorun"
require "track_relay"
require "track_relay/dsl/param_builder"

class ParamBuilderTest < Minitest::Test
  ParamBuilder = TrackRelay::DSL::ParamBuilder

  def test_integer_records_param_schema_with_type_integer
    builder = ParamBuilder.new(:foo)
    builder.integer(:article_id, required: true)

    schema = builder.params[:article_id]
    assert_equal :article_id, schema.name
    assert_equal :integer, schema.type
    assert_equal true, schema.required
  end

  def test_string_records_param_schema_with_max_option
    builder = ParamBuilder.new(:foo)
    builder.string(:article_slug, max: 100)

    schema = builder.params[:article_slug]
    assert_equal :string, schema.type
    assert_equal 100, schema.max
  end

  def test_float_records_param_schema_with_type_float
    builder = ParamBuilder.new(:foo)
    builder.float(:cart_total)

    assert_equal :float, builder.params[:cart_total].type
  end

  def test_boolean_records_param_schema_with_type_boolean
    builder = ParamBuilder.new(:foo)
    builder.boolean(:is_premium)

    assert_equal :boolean, builder.params[:is_premium].type
  end

  def test_datetime_records_param_schema_with_type_datetime
    builder = ParamBuilder.new(:foo)
    builder.datetime(:occurred_at)

    assert_equal :datetime, builder.params[:occurred_at].type
  end

  def test_mixing_types_in_one_block
    builder = ParamBuilder.new(:checkout)
    builder.integer(:order_id, required: true)
    builder.string(:tier)
    builder.float(:total_cents)
    builder.boolean(:gift_wrap)
    builder.datetime(:placed_at)

    assert_equal %i[order_id tier total_cents gift_wrap placed_at], builder.params.keys
    assert_equal :integer, builder.params[:order_id].type
    assert_equal :string, builder.params[:tier].type
    assert_equal :float, builder.params[:total_cents].type
    assert_equal :boolean, builder.params[:gift_wrap].type
    assert_equal :datetime, builder.params[:placed_at].type
  end

  def test_string_supports_in_format_and_sanitize_options
    sanitize = ->(v) { v.to_s.strip }
    builder = ParamBuilder.new(:foo)
    builder.string(:tier,
      required: true,
      max: 20,
      in: %w[free pro enterprise],
      format: /\A[a-z]+\z/,
      sanitize: sanitize)

    schema = builder.params[:tier]
    assert_equal true, schema.required
    assert_equal 20, schema.max
    assert_equal %w[free pro enterprise], schema.in
    assert_equal(/\A[a-z]+\z/, schema.format)
    assert_same sanitize, schema.sanitize
  end

  def test_user_property_accumulates_separately_from_params
    builder = ParamBuilder.new(:foo)
    builder.integer(:foo_id)
    builder.user_property(:plan, :string)

    assert_equal({foo_id: builder.params[:foo_id]}, builder.params)
    assert_equal({plan: :string}, builder.user_properties)
  end

  def test_multiple_user_properties_accumulate
    builder = ParamBuilder.new(:foo)
    builder.user_property(:plan, :string)
    builder.user_property(:onboarded, :boolean)

    assert_equal({plan: :string, onboarded: :boolean}, builder.user_properties)
  end
end
