# frozen_string_literal: true

require "minitest/autorun"
require "track_relay"
require "track_relay/event_definition"
require "track_relay/validators/catalog_validator"

class CatalogValidatorTest < Minitest::Test
  ParamSchema = TrackRelay::EventDefinition::ParamSchema
  CatalogValidator = TrackRelay::Validators::CatalogValidator

  def build_definition(name:, params: {})
    schemas = params.transform_values do |type|
      ParamSchema.new(name: :placeholder, type: type)
    end
    schemas.each { |k, v| schemas[k] = ParamSchema.new(name: k, type: v.type) }
    TrackRelay::EventDefinition.new(name: name, params: schemas)
  end

  def test_legal_definition_passes
    definition = build_definition(
      name: :article_viewed,
      params: {article_id: :integer, article_slug: :string}
    )

    CatalogValidator.validate!(definition) # should not raise
  end

  def test_definition_with_reserved_user_param_raises
    definition = build_definition(name: :foo, params: {user: :string})

    error = assert_raises(TrackRelay::ReservedKeyError) do
      CatalogValidator.validate!(definition)
    end
    assert_match(/:user/, error.message)
    assert_match(/reserved/i, error.message)
  end

  def test_definition_with_reserved_visitor_token_param_raises
    definition = build_definition(name: :foo, params: {visitor_token: :string})

    error = assert_raises(TrackRelay::ReservedKeyError) do
      CatalogValidator.validate!(definition)
    end
    assert_match(/:visitor_token/, error.message)
  end

  def test_definition_with_reserved_client_id_param_raises
    definition = build_definition(name: :foo, params: {client_id: :string})

    assert_raises(TrackRelay::ReservedKeyError) do
      CatalogValidator.validate!(definition)
    end
  end

  def test_definition_with_reserved_request_param_raises
    definition = build_definition(name: :foo, params: {request: :string})

    assert_raises(TrackRelay::ReservedKeyError) do
      CatalogValidator.validate!(definition)
    end
  end

  def test_definition_with_ga4_reserved_event_name_raises
    definition = build_definition(name: :page_view)

    assert_raises(TrackRelay::Ga4ConstraintError) do
      CatalogValidator.validate!(definition)
    end
  end

  def test_definition_with_too_many_params_raises
    params = (1..26).each_with_object({}) { |i, h| h[:"p#{i}"] = :string }
    definition = build_definition(name: :many_params, params: params)

    assert_raises(TrackRelay::Ga4ConstraintError) do
      CatalogValidator.validate!(definition)
    end
  end

  def test_definition_with_invalid_param_name_raises
    bad_key = :"Bad-Name"
    schemas = {bad_key => ParamSchema.new(name: bad_key, type: :string)}
    definition = TrackRelay::EventDefinition.new(name: :foo, params: schemas)

    assert_raises(TrackRelay::Ga4ConstraintError) do
      CatalogValidator.validate!(definition)
    end
  end

  def test_reserved_key_error_message_suggests_renaming
    definition = build_definition(name: :foo, params: {user: :string})

    error = assert_raises(TrackRelay::ReservedKeyError) do
      CatalogValidator.validate!(definition)
    end
    assert_match(/rename/i, error.message)
  end
end
