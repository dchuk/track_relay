# frozen_string_literal: true

require "minitest/autorun"
require "track_relay"

class CatalogTest < Minitest::Test
  def setup
    TrackRelay::Catalog.clear!
  end

  def teardown
    TrackRelay::Catalog.clear!
  end

  def test_track_relay_catalog_block_registers_typed_event
    TrackRelay.catalog do
      event :article_viewed do
        integer :article_id, required: true
      end
    end

    definition = TrackRelay::Catalog.lookup(:article_viewed)
    refute_nil definition
    assert_equal :article_viewed, definition.name
    assert_equal :integer, definition.params[:article_id].type
    assert_equal true, definition.params[:article_id].required
  end

  def test_double_register_of_same_event_raises_catalog_error
    TrackRelay.catalog do
      event :foo do
      end
    end

    error = assert_raises(TrackRelay::CatalogError) do
      TrackRelay.catalog do
        event :foo do
        end
      end
    end
    assert_match(/foo/, error.message)
  end

  def test_clear_empties_registry
    TrackRelay.catalog do
      event :foo do
        integer :n
      end
    end

    refute_nil TrackRelay::Catalog.lookup(:foo)
    TrackRelay::Catalog.clear!
    assert_nil TrackRelay::Catalog.lookup(:foo)
  end

  def test_defined_returns_boolean_for_registered_event
    refute TrackRelay::Catalog.defined?(:never_registered)

    TrackRelay.catalog do
      event :foo do
      end
    end

    assert TrackRelay::Catalog.defined?(:foo)
  end

  def test_all_returns_array_of_definitions
    TrackRelay.catalog do
      event :foo do
      end
      event :bar do
      end
    end

    names = TrackRelay::Catalog.all.map(&:name)
    assert_equal [:foo, :bar].sort, names.sort
  end

  def test_all_returns_frozen_array
    TrackRelay.catalog do
      event :foo do
      end
    end

    assert_predicate TrackRelay::Catalog.all, :frozen?
  end

  def test_lookup_returns_nil_for_unknown_event
    assert_nil TrackRelay::Catalog.lookup(:nope)
  end

  def test_user_property_at_top_level_registers_globally
    TrackRelay.catalog do
      user_property :plan, :string
    end

    assert_equal :string, TrackRelay::Catalog.user_properties[:plan]
  end
end
