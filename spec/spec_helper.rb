# frozen_string_literal: true

require 'testsort'
require 'tmpdir'
require 'fileutils'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  # config.disable_monkey_patching!

  config.expose_dsl_globally = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Guard: fail if any spec writes to the real project's testsort/ storage dir
  project_root = File.expand_path('..', __dir__)
  storage_dir = File.join(project_root, Testsort::Paths::GEM_STORAGE)

  config.after(:each) do
    if File.directory?(storage_dir) && Dir.entries(storage_dir).any? { |e| %w[shape coverage_matrix.bin spec_to_index.json].include?(e) }
      raise "Spec wrote to real project storage directory: #{storage_dir}"
    end
  end

  # Reset Testsort configuration to a known default after each example so
  # leaked state (e.g. line_level flipped to true by a prior spec) doesn't
  # affect unrelated tests. Default the project hook to Radfahrausbildung —
  # that matches the values previously hardcoded gem-wide, keeping existing
  # specs green without per-spec setup.
  reset_configuration = lambda do
    fresh = Testsort::Configuration.new
    fresh.project = Testsort::Projects::Radfahrausbildung.new
    Testsort.instance_variable_set(:@configuration, fresh)
  end
  config.before(:suite) { reset_configuration.call }
  config.after(:each)   { reset_configuration.call }
end
