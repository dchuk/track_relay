# frozen_string_literal: true

require "test_helper"
require "json"
require "tempfile"
require "tmpdir"
require "pathname"
require "track_relay/manifest"

# Unit coverage for {TrackRelay::Manifest}.
#
# Two responsibilities, tested in isolation from Rails / the Railtie:
#
#   1. {TrackRelay::Manifest.generate(catalog:)} returns a Hash matching
#      the 02-CONTEXT shape consumed by the JS client (Plan 02-05):
#
#        {
#          version: TrackRelay::VERSION,
#          generated_at: <ISO8601 string>,
#          events: {
#            "<event_name>" => {
#              params: {"<param>" => "<type>"},
#              required: ["<required_param_name>"]
#            }
#          }
#        }
#
#   2. {TrackRelay::Manifest.write!(path:)} writes pretty-printed JSON to
#      `path`, returns the path, and `mkdir_p`s the parent directory so a
#      fresh checkout (e.g. the Combustion dummy app at `test/internal/`,
#      which has no `public/` directory) does NOT crash on first run with
#      `Errno::ENOENT`. The parent-dir guard is load-bearing — without it
#      the gem's own integration tests would fail before they could run.
class ManifestTest < ActiveSupport::TestCase
  setup do
    TrackRelay::Catalog.clear!
  end

  # ---- generate: shape ---------------------------------------------------

  test "generate returns the documented top-level shape" do
    TrackRelay.catalog do
      event :purchase do
        float :value, required: true
        string :currency
      end
    end

    output = TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)

    assert_equal TrackRelay::VERSION, output[:version]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, output[:generated_at])
    assert output[:events].is_a?(Hash)
    assert output[:events].key?("purchase")
  end

  test "generate emits params as Hash{string => type-string} and required[] as strings" do
    TrackRelay.catalog do
      event :purchase do
        float :value, required: true
        string :currency
      end
    end

    output = TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)
    purchase = output[:events]["purchase"]

    assert_equal({"value" => "float", "currency" => "string"}, purchase[:params])
    assert_equal ["value"], purchase[:required]
  end

  test "generate covers all 5 ParamSchema types" do
    TrackRelay.catalog do
      event :every_type do
        integer :item_id
        string :item_name
        float :price
        boolean :on_sale
        datetime :expires_at
      end
    end

    output = TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)
    params = output[:events]["every_type"][:params]

    assert_equal "integer", params["item_id"]
    assert_equal "string", params["item_name"]
    assert_equal "float", params["price"]
    assert_equal "boolean", params["on_sale"]
    assert_equal "datetime", params["expires_at"]
  end

  test "generate includes an empty required[] when no params are required" do
    TrackRelay.catalog do
      event :search do
        string :query
      end
    end

    output = TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)
    search = output[:events]["search"]

    # The `required` key MUST exist (the JS client iterates it
    # unconditionally) — and MUST be an empty array, not nil.
    assert_equal [], search[:required]
    assert search.key?(:required), "required key must be present even when empty"
  end

  test "generate produces JSON.parse-able output via JSON.pretty_generate" do
    TrackRelay.catalog do
      event :purchase do
        float :value, required: true
      end
    end

    output = TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)
    parsed = JSON.parse(JSON.pretty_generate(output))

    assert_equal TrackRelay::VERSION, parsed["version"]
    assert_equal "float", parsed.dig("events", "purchase", "params", "value")
    assert_equal ["value"], parsed.dig("events", "purchase", "required")
  end

  test "generate returns an empty events hash when the catalog is empty" do
    output = TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)

    assert_equal({}, output[:events])
    assert_equal TrackRelay::VERSION, output[:version]
  end

  # ---- write! ------------------------------------------------------------

  test "write! returns the path it wrote to" do
    Tempfile.create(["manifest", ".json"]) do |f|
      result = TrackRelay::Manifest.write!(path: f.path)
      assert_equal f.path, result.to_s
    end
  end

  test "write! emits pretty-printed JSON.parse-able content" do
    TrackRelay.catalog do
      event :purchase do
        float :value, required: true
        string :currency
      end
    end

    Tempfile.create(["manifest", ".json"]) do |f|
      TrackRelay::Manifest.write!(path: f.path)
      content = File.read(f.path)

      # Pretty-printed JSON includes line breaks and indentation;
      # JSON.generate (compact) would not. Assert at least one newline.
      assert_includes content, "\n"
      parsed = JSON.parse(content)
      assert_equal "float", parsed.dig("events", "purchase", "params", "value")
      assert_equal ["value"], parsed.dig("events", "purchase", "required")
    end
  end

  test "creates_parent_directory: write! mkdir_p's a missing parent dir" do
    # The Combustion dummy app at `test/internal/` ships without a
    # `public/` directory. Without `FileUtils.mkdir_p(File.dirname(path))`
    # the very first `Manifest.write!` call in the gem's own test suite
    # crashes with `Errno::ENOENT`. Guard it explicitly.
    Dir.mktmpdir do |root|
      target = Pathname(root).join("brand_new_subdir", "track_relay_catalog.json")

      refute File.exist?(File.dirname(target)),
        "precondition: parent dir must NOT exist before write!"

      TrackRelay::Manifest.write!(path: target.to_s)

      assert File.exist?(target),
        "manifest file should exist after write!"
      assert File.directory?(File.dirname(target)),
        "missing parent directory should have been created by mkdir_p"
    end
  end
end
