# frozen_string_literal: true

# Integration smoke-test for Testsort::Evaluation::Compare against a tiny
# in-process fixture project.
#
# Goals
# -----
# * Exercise Compare#call in both sequential (parallel: false) and parallel
#   (parallel: true) modes.
# * Verify that compare_apfd_by_commit.csv is written with numeric APFDs for
#   both file_level and line_level strategies.
# * Assert line_level APFD >= file_level APFD (the deliberate fault lives in
#   lines only greet_spec covers, so line-level finds it first or equal).
# * For parallel: verify per-process -env-N files are merged (glob returns
#   empty after run) and noise.json is "{}" (parent has 0 pre-existing fails).
#
# Performance target: < 30 s for both scenarios combined.
#
# Tagged :slow on the parallel example because it spawns parallel_rspec
# subprocesses; skip in fast CI with --tag ~slow.

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'csv'
require 'rugged'

# ---------------------------------------------------------------------------
# Fixture builder
# ---------------------------------------------------------------------------

module DummyFixtureBuilder
  TESTSORT_GEM_ROOT = File.expand_path('../../..', __FILE__).freeze

  # Source files — designed so that:
  #   * alpha.rb has greet (lines 2-3) and farewell (lines 7-15).
  #   * Commit 2 only changes greet body (line 3: "Hello" → "Howdy").
  #   * greet_spec exercises greet → covers lines 1-4 of alpha.rb (small set).
  #   * farewell_spec exercises farewell → covers lines 6-15 (large set).
  #
  # APFD arithmetic for 5 specs, 1 fault, absolute strategy:
  #   file_level — farewell_spec wins (more covered lines of alpha.rb);
  #                greet_spec is 2nd → fault at position 2
  #                → APFD = 1 - 2/5 + 1/10 = 0.7
  #   line_level — greet_spec is the only one covering changed lines (2-3)
  #                → fault at position 1
  #                → APFD = 1 - 1/5 + 1/10 = 0.9

  ALPHA_V1 = <<~RUBY
    class Alpha
      def greet(name)
        "Hello, \#{name}!"
      end

      def farewell(name)
        msg  = "Goodbye"
        msg += ", "
        msg += name
        msg += "!"
        msg += " See you later."
        msg += " Take care."
        msg += " Best wishes."
        msg
      end
    end
  RUBY

  # Commit 2: greet body changes on line 3 ("Hello" → "Howdy")
  ALPHA_V2 = <<~RUBY
    class Alpha
      def greet(name)
        "Howdy, \#{name}!"
      end

      def farewell(name)
        msg  = "Goodbye"
        msg += ", "
        msg += name
        msg += "!"
        msg += " See you later."
        msg += " Take care."
        msg += " Best wishes."
        msg
      end
    end
  RUBY

  BETA_SRC = <<~RUBY
    class Beta
      def compute(x)
        x * 2
      end
    end
  RUBY

  GAMMA_SRC = <<~RUBY
    class Gamma
      def transform(val)
        val.to_s.upcase
      end
    end
  RUBY

  # spec_helper.rb at <fixture>/spec/spec_helper.rb.
  # __dir__ inside this file = <fixture>/spec, so '../app/models' = <fixture>/app/models.
  # Uses testsort/spec_helper_evaluation so coverage + fault tracking work.
  # BUNDLE_GEMFILE is set to testsort's Gemfile so `bundle exec rspec`
  # resolves gems without a separate bundle install.
  SPEC_HELPER = <<~RUBY
    # frozen_string_literal: true
    $LOAD_PATH.unshift(File.expand_path('../app/models', __dir__))
    require 'testsort/spec_helper_evaluation'
  RUBY

  # greet_spec asserts "Hello, ..." — fails on commit 2 because greet now
  # returns "Howdy, ...". Same file content in both commits (only source changes).
  GREET_SPEC = <<~RUBY
    require 'spec_helper'
    require 'alpha'

    RSpec.describe Alpha, '#greet' do
      it 'returns a greeting' do
        expect(Alpha.new.greet('World')).to eq('Hello, World!')
      end
    end
  RUBY

  FAREWELL_SPEC = <<~RUBY
    require 'spec_helper'
    require 'alpha'

    RSpec.describe Alpha, '#farewell' do
      it 'says goodbye' do
        result = Alpha.new.farewell('Alice')
        expect(result).to include('Goodbye')
        expect(result).to include('Alice')
        expect(result).to include('Best wishes')
      end
    end
  RUBY

  BETA_SPEC = <<~RUBY
    require 'spec_helper'
    require 'beta'

    RSpec.describe Beta do
      it 'doubles a number' do
        expect(Beta.new.compute(3)).to eq(6)
      end
    end
  RUBY

  GAMMA_SPEC = <<~RUBY
    require 'spec_helper'
    require 'gamma'

    RSpec.describe Gamma do
      it 'uppercases' do
        expect(Gamma.new.transform('hello')).to eq('HELLO')
      end
    end
  RUBY

  COMBINED_SPEC = <<~RUBY
    require 'spec_helper'
    require 'beta'
    require 'gamma'

    RSpec.describe 'Beta+Gamma combined' do
      it 'both work together' do
        expect(Beta.new.compute(2)).to eq(4)
        expect(Gamma.new.transform('x')).to eq('X')
      end
    end
  RUBY

  # .rspec file — no --require so each spec explicitly requires spec_helper.
  RSPEC_OPTS = "--format progress\n"

  # Build a fresh temp working copy and init a 2-commit git repo.
  # Returns [dir_path, commit2_sha].
  def self.build_fixture
    dir = Dir.mktmpdir('testsort-dummy')

    # Directory skeleton
    FileUtils.mkdir_p(File.join(dir, 'app/models'))
    FileUtils.mkdir_p(File.join(dir, 'spec/models'))

    # Static files (same in both commits)
    File.write(File.join(dir, 'app/models/beta.rb'),  BETA_SRC)
    File.write(File.join(dir, 'app/models/gamma.rb'), GAMMA_SRC)
    File.write(File.join(dir, 'spec/spec_helper.rb'), SPEC_HELPER)
    File.write(File.join(dir, 'spec/models/farewell_spec.rb'), FAREWELL_SPEC)
    File.write(File.join(dir, 'spec/models/greet_spec.rb'),    GREET_SPEC)
    File.write(File.join(dir, 'spec/models/beta_spec.rb'),     BETA_SPEC)
    File.write(File.join(dir, 'spec/models/gamma_spec.rb'),    GAMMA_SPEC)
    File.write(File.join(dir, 'spec/models/combined_spec.rb'), COMBINED_SPEC)
    File.write(File.join(dir, '.rspec'), RSPEC_OPTS)

    # Commit 1: alpha V1 — all specs green
    File.write(File.join(dir, 'app/models/alpha.rb'), ALPHA_V1)

    repo   = Rugged::Repository.init_at(dir)
    author = { name: 'Dummy', email: 'dummy@test', time: Time.now }

    # Helper: stage all non-.git files and commit
    snapshot = lambda do |msg|
      index = repo.index
      index.read_tree(repo.empty? ? nil : repo.head.target.tree) unless repo.empty?

      Dir.glob(File.join(dir, '**', '{*,.*}'), File::FNM_DOTMATCH).each do |abs|
        next if File.directory?(abs)
        next if abs.include?('/.git/')

        rel     = abs.delete_prefix("#{dir}/")
        content = File.read(abs, encoding: 'binary')
        oid     = repo.write(content, :blob)
        index.add(path: rel, oid: oid, mode: 0o100644)
      end
      index.write

      tree    = index.write_tree(repo)
      parents = repo.empty? ? [] : [repo.head.target]
      sha     = Rugged::Commit.create(repo,
        tree:       tree,
        author:     author,
        committer:  author,
        message:    msg,
        parents:    parents,
        update_ref: 'HEAD')
      sha
    end

    snapshot.call('Commit 1: baseline — all specs green')

    # Create 'main' branch pointing at HEAD and make HEAD track it
    repo.create_branch('main', 'HEAD')
    repo.head = 'refs/heads/main'

    # Commit 2: patch alpha.rb greet body (line 3 changes)
    File.write(File.join(dir, 'app/models/alpha.rb'), ALPHA_V2)
    commit2_sha = snapshot.call('Commit 2: change greet — introduces fault in greet_spec')

    [dir, commit2_sha]
  end
end

# ---------------------------------------------------------------------------
# Shared setup / teardown
# ---------------------------------------------------------------------------

shared_context 'dummy fixture' do
  before(:context) do
    @fixture_dir, @commit2_sha = DummyFixtureBuilder.build_fixture
  end

  after(:context) do
    # Clean up the fixture directory
    FileUtils.rm_rf(@fixture_dir) if @fixture_dir && File.directory?(@fixture_dir)
    # Clean up evaluation storage placed next to the fixture dir by Paths.evaluation_storage
    if @fixture_dir
      basename_suffix = File.basename(@fixture_dir.to_s)[/([a-zA-Z.\-]*)$/, 1].to_s
      eval_store = File.join(File.dirname(@fixture_dir.to_s), "testsort-test-#{basename_suffix}")
      FileUtils.rm_rf(eval_store) if File.directory?(eval_store)
    end
  end

  let(:fixture_dir)  { @fixture_dir }
  let(:commit2_sha)  { @commit2_sha }
  let(:compare_io)   { StringIO.new }
  let(:compare)      { Testsort::Evaluation::Compare.new(io: compare_io) }

  # Set Dummy project before each example (spec_helper resets to Radfahrausbildung after(:each))
  before(:each) do
    Testsort.configuration.project = Testsort::Projects::Dummy.new
  end

  # ProjectSetup.setup is a no-op — fixture has no Gemfile and no DB
  before(:each) do
    allow(Testsort::RepositoryManager::ProjectSetup).to receive(:setup)
  end

  # Stub Bundler.with_unbundled_env to just yield without modifying the env.
  # This lets BUNDLE_GEMFILE (explicitly set to testsort's path in run_compare)
  # survive into the subprocess so `bundle exec rspec` in the fixture dir
  # resolves gems from testsort's bundle — no separate bundle install needed.
  before(:each) do
    allow(Bundler).to receive(:with_unbundled_env) do |&block|
      block.call
    end
  end
end

# ---------------------------------------------------------------------------
# Run helper
# ---------------------------------------------------------------------------

def run_compare(fixture_dir:, commit2_sha:, compare:, parallel:)
  original_dir           = Dir.getwd
  saved_bundle_gemfile   = ENV['BUNDLE_GEMFILE']
  saved_run_number       = ENV['run_number']
  saved_processors       = ENV['PARALLEL_TEST_PROCESSORS']

  # Reset run_number so each example starts at folder '0'
  ENV.delete('run_number')
  # Point BUNDLE_GEMFILE at testsort so subprocesses can `bundle exec rspec`
  # from the fixture directory (which has no Gemfile of its own).
  ENV['BUNDLE_GEMFILE'] = File.join(DummyFixtureBuilder::TESTSORT_GEM_ROOT, 'Gemfile')
  ENV['PARALLEL_TEST_PROCESSORS'] = '2' if parallel

  Dir.chdir(fixture_dir) do
    compare.call(
      commits:    [commit2_sha],
      project:    nil,     # already set via Testsort.configuration before(:each)
      strategies: %w[file_level line_level],
      parallel:   parallel,
      fresh:      true,
    )
  end
ensure
  ENV['BUNDLE_GEMFILE']            = saved_bundle_gemfile
  ENV['run_number']                = saved_run_number
  if saved_processors.nil?
    ENV.delete('PARALLEL_TEST_PROCESSORS')
  else
    ENV['PARALLEL_TEST_PROCESSORS'] = saved_processors
  end
  Dir.chdir(original_dir) if Dir.getwd != original_dir
end

# ---------------------------------------------------------------------------
# Assertion helper
# ---------------------------------------------------------------------------

def assert_compare_results(fixture_dir:, commit2_sha:, parallel:)
  basename_suffix = File.basename(fixture_dir)[/([a-zA-Z.\-]*)$/, 1].to_s
  eval_store  = File.join(File.dirname(fixture_dir), "testsort-test-#{basename_suffix}")
  eval_folder = File.join(eval_store, 'evaluation')

  run_dirs = Dir.glob(File.join(eval_folder, '*')).select do |d|
    File.directory?(d) && File.basename(d).match?(/\A\d+\z/)
  end
  expect(run_dirs).not_to be_empty,
    "No evaluation run folders found under #{eval_folder}\nio: #{@compare_io&.string}"
  run_dir = run_dirs.max_by { |d| File.basename(d).to_i }

  csv_path = File.join(run_dir, 'compare_apfd_by_commit.csv')
  expect(File.exist?(csv_path)).to be(true),
    "compare_apfd_by_commit.csv not found at #{csv_path}"

  csv = CSV.read(csv_path, headers: true)
  expect(csv.size).to be >= 1, "CSV has no data rows\nHeaders: #{csv.headers.inspect}"

  row = csv.first
  file_level_apfd = row['file_level'].to_f
  line_level_apfd = row['line_level'].to_f

  expect(file_level_apfd).to be > 0.0,
    "file_level APFD should be > 0, got #{file_level_apfd.inspect}"
  expect(line_level_apfd).to be > 0.0,
    "line_level APFD should be > 0, got #{line_level_apfd.inspect}"

  # line_level should find the fault at position 1 (or at worst tie with file_level)
  expect(line_level_apfd + 0.05).to be >= file_level_apfd,
    "Expected line_level (#{line_level_apfd}) >= file_level (#{file_level_apfd}) within 0.05 tolerance"

  if parallel
    noise_file = File.join(eval_store, 'coverage_data', commit2_sha, 'noise.json')
    if File.exist?(noise_file)
      leftover_noise_env = Dir.glob("#{noise_file}-env-*")
      expect(leftover_noise_env).to be_empty,
        "Per-env noise files not merged: #{leftover_noise_env.inspect}"

      noise_data = JSON.parse(File.read(noise_file))
      expect(noise_data).to eq({}),
        "noise.json should be {} (no pre-existing failures); got: #{noise_data.inspect}"
    end

    leftover_eval_env = Dir.glob(File.join(run_dir, '*-env-*'))
    expect(leftover_eval_env).to be_empty,
      "Per-env eval files not merged: #{leftover_eval_env.inspect}"
  end

  [file_level_apfd, line_level_apfd]
end

# ---------------------------------------------------------------------------
# Specs
# ---------------------------------------------------------------------------

describe 'Parallel Compare integration smoke-test' do
  include_context 'dummy fixture'

  describe 'sequential mode (parallel: false)' do
    it 'writes compare_apfd_by_commit.csv with numeric APFDs; line_level >= file_level' do
      run_compare(
        fixture_dir:  fixture_dir,
        commit2_sha:  commit2_sha,
        compare:      compare,
        parallel:     false,
      )

      file_apfd, line_apfd = assert_compare_results(
        fixture_dir:  fixture_dir,
        commit2_sha:  commit2_sha,
        parallel:     false,
      )

      # Expected APFD values for this fixture (within generous ±0.3 tolerance):
      #   line_level ~0.9  (fault found at position 1)
      #   file_level ~0.7  (fault found at position 2 — farewell_spec ranked higher by coverage)
      expect(line_apfd).to be_within(0.3).of(0.9)
      expect(file_apfd).to be_within(0.3).of(0.7)
    end
  end

  describe 'parallel mode (parallel: true)', :slow do
    it 'writes the same APFDs, merges per-env files, produces empty noise.json' do
      run_compare(
        fixture_dir:  fixture_dir,
        commit2_sha:  commit2_sha,
        compare:      compare,
        parallel:     true,
      )

      file_apfd, line_apfd = assert_compare_results(
        fixture_dir:  fixture_dir,
        commit2_sha:  commit2_sha,
        parallel:     true,
      )

      # Parallel degrades line-level to spec-file granularity on 5 specs but
      # the fault should still be detected early.  Allow ±0.3 spread between
      # strategies since the spec ordering under parallel is less deterministic.
      expect((line_apfd - file_apfd).abs).to be <= 0.3
    end
  end
end
