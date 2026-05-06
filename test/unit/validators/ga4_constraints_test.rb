# frozen_string_literal: true

require "minitest/autorun"
require "track_relay"
require "track_relay/validators/ga4_constraints"

class Ga4ConstraintsTest < Minitest::Test
  Ga4Constraints = TrackRelay::Validators::Ga4Constraints

  # ---------------- validate_event_name! ----------------

  def test_validate_event_name_accepts_valid_snake_case_symbol
    Ga4Constraints.validate_event_name!(:article_viewed) # should not raise
  end

  def test_validate_event_name_accepts_valid_snake_case_string
    Ga4Constraints.validate_event_name!("article_viewed") # should not raise
  end

  def test_validate_event_name_accepts_lowercase_with_digits_and_underscores
    Ga4Constraints.validate_event_name!(:plan_v2_upgraded)
  end

  def test_validate_event_name_rejects_uppercase
    error = assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:ArticleViewed)
    end
    assert_match(/ArticleViewed/, error.message)
  end

  def test_validate_event_name_rejects_dashes
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:"article-viewed")
    end
  end

  def test_validate_event_name_rejects_starting_with_digit
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:"3d_print")
    end
  end

  def test_validate_event_name_rejects_starting_with_underscore
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:_internal)
    end
  end

  def test_validate_event_name_rejects_41_char_name
    name = ("a" * 41).to_sym
    error = assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(name)
    end
    assert_match(/40/, error.message)
  end

  def test_validate_event_name_accepts_40_char_name
    Ga4Constraints.validate_event_name!(("a" * 40).to_sym)
  end

  def test_validate_event_name_rejects_ga4_reserved_page_view
    error = assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:page_view)
    end
    assert_match(/page_view/, error.message)
    assert_match(/reserved/i, error.message)
  end

  def test_validate_event_name_rejects_ga4_reserved_session_start
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:session_start)
    end
  end

  def test_validate_event_name_rejects_ga4_reserved_user_engagement
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:user_engagement)
    end
  end

  def test_validate_event_name_rejects_ga4_reserved_first_visit
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:first_visit)
    end
  end

  def test_validate_event_name_rejects_ga4_reserved_video_complete
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_event_name!(:video_complete)
    end
  end

  # ---------------- validate_param_count! ----------------

  def test_validate_param_count_accepts_25_params
    params = (1..25).each_with_object({}) { |i, h| h[:"p#{i}"] = :stub }
    Ga4Constraints.validate_param_count!(params)
  end

  def test_validate_param_count_rejects_26_params
    params = (1..26).each_with_object({}) { |i, h| h[:"p#{i}"] = :stub }
    error = assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_param_count!(params)
    end
    assert_match(/25/, error.message)
    assert_match(/26/, error.message)
  end

  def test_validate_param_count_accepts_zero_params
    Ga4Constraints.validate_param_count!({})
  end

  # ---------------- validate_param_name! ----------------

  def test_validate_param_name_accepts_valid_name
    Ga4Constraints.validate_param_name!(:article_id)
  end

  def test_validate_param_name_rejects_uppercase
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_param_name!(:ArticleId)
    end
  end

  def test_validate_param_name_rejects_dashes
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_param_name!(:"article-id")
    end
  end

  def test_validate_param_name_rejects_41_chars
    assert_raises(TrackRelay::Ga4ConstraintError) do
      Ga4Constraints.validate_param_name!(("a" * 41).to_sym)
    end
  end

  def test_validate_param_name_accepts_40_chars
    Ga4Constraints.validate_param_name!(("a" * 40).to_sym)
  end
end
