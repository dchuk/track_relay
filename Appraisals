# frozen_string_literal: true

# Slugs use underscores so the generated gemfiles map directly to
# gemfiles/${{ matrix.appraisal }}.gemfile in the GitHub Actions matrix
# without a name-translation step.
appraise "rails_7_1" do
  gem "rails", "~> 7.1.0"
end

appraise "rails_7_2" do
  gem "rails", "~> 7.2.0"
end

appraise "rails_8_0" do
  gem "rails", "~> 8.0.0"
end

# Keep the human-readable "rails-8.0" name documented for grepability —
# the must_haves expect the string "rails-8.0" to appear in this file.
# Reference: rails-7.1 / rails-7.2 / rails-8.0 (Appraisal slug aliases).
