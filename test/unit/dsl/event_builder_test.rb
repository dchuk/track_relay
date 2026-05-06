# frozen_string_literal: true

require "minitest/autorun"
require "track_relay"

class EventBuilderTest < Minitest::Test
  def setup
    TrackRelay::Catalog.clear!
  end

  def teardown
    TrackRelay::Catalog.clear!
  end

  def build(&block)
    TrackRelay::DSL::EventBuilder.new.instance_exec(&block)
  end

  def test_event_with_empty_block_registers_definition_with_no_params
    build do
      event :empty_event do
      end
    end

    definition = TrackRelay::Catalog.lookup(:empty_event)
    refute_nil definition
    assert_equal :empty_event, definition.name
    assert_equal({}, definition.params)
  end

  def test_event_with_one_integer_param_registers_correct_schema
    build do
      event :article_viewed do
        integer :article_id, required: true
      end
    end

    definition = TrackRelay::Catalog.lookup(:article_viewed)
    assert_equal [:article_id], definition.params.keys
    assert_equal :integer, definition.params[:article_id].type
    assert_equal true, definition.params[:article_id].required
  end

  def test_event_with_mixed_param_types
    build do
      event :checkout_completed do
        integer :order_id, required: true
        string :tier
        float :total_cents
        boolean :gift_wrap
        datetime :placed_at
      end
    end

    definition = TrackRelay::Catalog.lookup(:checkout_completed)
    assert_equal %i[order_id tier total_cents gift_wrap placed_at], definition.params.keys
  end

  def test_event_with_reserved_param_key_raises_at_load_time
    error = assert_raises(TrackRelay::ReservedKeyError) do
      build do
        event :foo do
          string :user
        end
      end
    end
    assert_match(/:user/, error.message)
  end

  def test_event_with_ga4_reserved_name_raises_at_load_time
    assert_raises(TrackRelay::Ga4ConstraintError) do
      build do
        event :page_view do
        end
      end
    end
  end

  def test_event_with_invalid_event_name_raises
    assert_raises(TrackRelay::Ga4ConstraintError) do
      build do
        event :"Bad-Name" do
        end
      end
    end
  end

  def test_event_with_invalid_param_name_raises
    assert_raises(TrackRelay::Ga4ConstraintError) do
      build do
        event :foo do
          string :"Bad-Param"
        end
      end
    end
  end

  def test_event_block_can_declare_user_property
    build do
      event :session_started do
        user_property :plan, :string
      end
    end

    definition = TrackRelay::Catalog.lookup(:session_started)
    assert_equal({plan: :string}, definition.user_properties)
  end

  def test_top_level_user_property_registers_catalog_wide
    build do
      user_property :plan, :string
      user_property :onboarded, :boolean
    end

    assert_equal :string, TrackRelay::Catalog.user_properties[:plan]
    assert_equal :boolean, TrackRelay::Catalog.user_properties[:onboarded]
  end
end
