# frozen_string_literal: true

require_relative "lib/track_relay/version"

Gem::Specification.new do |spec|
  spec.name = "track_relay"
  spec.version = TrackRelay::VERSION
  spec.authors = ["Darrin Demchuk"]
  spec.email = ["darrindemchuk@gmail.com"]

  spec.summary = "One catalog, many destinations: typed analytics events for Rails."
  spec.description = <<~DESC
    track_relay eliminates dual event vocabularies between marketing and product
    analytics in Rails apps. Define events once in a Ruby DSL catalog, then dispatch
    them through ActiveSupport::Notifications to multiple destinations (GA4, Ahoy,
    your own subscribers) with shared payload validation and a single tracking call.
  DESC
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = "https://github.com/dchuk/track_relay"
  spec.metadata["source_code_uri"] = "https://github.com/dchuk/track_relay"
  spec.metadata["changelog_uri"] = "https://github.com/dchuk/track_relay/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.homepage = spec.metadata["homepage_uri"]

  spec.files = Dir.glob("lib/**/*") + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.1"

  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "combustion", "~> 1.3"
  spec.add_development_dependency "minitest", "~> 5.16"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec-core", "~> 3.13"
  spec.add_development_dependency "rspec-expectations", "~> 3.13"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "standard"
end
