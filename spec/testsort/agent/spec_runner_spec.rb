# frozen_string_literal: true

require 'spec_helper'

describe Testsort::Agent::SpecRunner do
  # -------------------------------------------------------------------------
  # Shared helpers
  # -------------------------------------------------------------------------

  # Build a minimal fake process status object.
  def fake_status(exitstatus)
    double('Process::Status', exitstatus: exitstatus, success?: exitstatus == 0)
  end

  # Default merge_files result used by most "happy path" tests.
  def default_merged
    { generated_at: Time.now.utc.iso8601, examples: { 'spec/a_spec.rb:1' => { 'status' => 'passed' } } }
  end

  # Stub Open3.capture3 to return the given stdout/stderr/status, capturing
  # the command string it was called with.
  def stub_open3(stdout: '', stderr: '', exitstatus: 0, &extra)
    captured = nil
    allow(Open3).to receive(:capture3) do |cmd|
      captured = cmd
      extra.call(cmd) if extra
      [stdout, stderr, fake_status(exitstatus)]
    end
    -> { captured }
  end

  # Stub Bundler.with_unbundled_env to just yield.
  before do
    allow(Bundler).to receive(:with_unbundled_env).and_yield
  end

  # Prevent actual filesystem glob/deletion and ResultCollector calls.
  before do
    allow(Dir).to receive(:glob).and_call_original
    # By default pretend there ARE result files after the run.
    allow(Dir).to receive(:glob).with(Testsort::Paths.agent_results_glob).and_return(
      ['testsort/agent_results.json']
    )
    allow(FileUtils).to receive(:rm_f).and_return(true)
    allow(Testsort::Agent::ResultCollector).to receive(:merge_files).and_return(default_merged)
  end

  # -------------------------------------------------------------------------
  # Error cases
  # -------------------------------------------------------------------------

  describe 'empty / blank input' do
    it 'raises Testsort::Error when specs is empty' do
      expect { described_class.run(specs: []) }
        .to raise_error(Testsort::Error, /no specs provided/)
    end

    it 'raises Testsort::Error when specs is nil' do
      expect { described_class.run(specs: nil) }
        .to raise_error(Testsort::Error, /no specs provided/)
    end

    it 'raises Testsort::Error when all specs are shared_examples' do
      expect { described_class.run(specs: ['spec/support/shared_examples/foo.rb']) }
        .to raise_error(Testsort::Error, /no specs provided/)
    end

    it 'raises Testsort::Error when all specs are non-spec/ paths' do
      expect { described_class.run(specs: ['/absolute/path/to/something.rb', 'app/models/user.rb']) }
        .to raise_error(Testsort::Error, /no specs provided/)
    end
  end

  # -------------------------------------------------------------------------
  # Filtering
  # -------------------------------------------------------------------------

  describe 'path filtering' do
    it 'drops shared_examples paths' do
      get_cmd = stub_open3

      described_class.run(specs: [
        'spec/support/shared_examples/user.rb',
        'spec/models/user_spec.rb',
      ])

      expect(get_cmd.call).to include('spec/models/user_spec.rb')
      expect(get_cmd.call).not_to include('shared_examples')
    end

    it 'drops non-spec/ paths' do
      get_cmd = stub_open3

      described_class.run(specs: [
        'app/models/user.rb',
        'spec/models/user_spec.rb',
      ])

      expect(get_cmd.call).to include('spec/models/user_spec.rb')
      expect(get_cmd.call).not_to include('app/models/user.rb')
    end

    it 'accepts ./spec/ paths' do
      get_cmd = stub_open3

      described_class.run(specs: ['./spec/models/post_spec.rb'])

      expect(get_cmd.call).to include('./spec/models/post_spec.rb')
    end
  end

  # -------------------------------------------------------------------------
  # Serial mode
  # -------------------------------------------------------------------------

  describe 'serial mode (parallel: false)' do
    let(:spec_helper_path) { Testsort::Agent::SpecRunner::SPEC_HELPER_AGENT_PATH }

    it 'builds a bundle exec rspec command' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/foo_spec.rb', 'spec/bar_spec.rb'])

      cmd = get_cmd.call
      expect(cmd).to include('bundle exec rspec')
      expect(cmd).not_to include('parallel_rspec')
    end

    it 'includes --require with the absolute path to spec_helper_agent.rb' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/foo_spec.rb'])

      expect(get_cmd.call).to include("--require #{spec_helper_path}")
      expect(spec_helper_path).to be_an_absolute_path
    end

    it 'includes --no-color' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/foo_spec.rb'])

      expect(get_cmd.call).to include('--no-color')
    end

    it 'includes the spec files' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/foo_spec.rb', 'spec/bar_spec.rb'])

      expect(get_cmd.call).to include('spec/foo_spec.rb')
      expect(get_cmd.call).to include('spec/bar_spec.rb')
    end

    it 'returns exit_status: 0, examples hash, and degraded_to_file_level: false' do
      stub_open3

      result = described_class.run(specs: ['spec/foo_spec.rb'])

      expect(result[:exit_status]).to eq(0)
      expect(result[:examples]).to eq(default_merged[:examples])
      expect(result[:degraded_to_file_level]).to be false
    end

    it 'returns exit_status: 1 when rspec exits 1 (some failures = success with results)' do
      stub_open3(exitstatus: 1)

      result = described_class.run(specs: ['spec/foo_spec.rb'])

      expect(result[:exit_status]).to eq(1)
    end
  end

  # -------------------------------------------------------------------------
  # Parallel mode
  # -------------------------------------------------------------------------

  describe 'parallel mode (parallel: true)' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return('2')
    end

    it 'builds a parallel_rspec command' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], parallel: true)

      expect(get_cmd.call).to include('parallel_rspec')
      expect(get_cmd.call).not_to match(/\bbundle exec rspec\b(?!.*parallel)/)
    end

    it 'includes --specify-groups with groups joined by |' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], parallel: true)

      expect(get_cmd.call).to include('--specify-groups')
      expect(get_cmd.call).to include('|')
    end

    it 'strips :line suffixes from spec keys' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/a_spec.rb:42', 'spec/b_spec.rb:7'], parallel: true)

      cmd = get_cmd.call
      expect(cmd).not_to include(':42')
      expect(cmd).not_to include(':7')
      expect(cmd).to include('spec/a_spec.rb')
      expect(cmd).to include('spec/b_spec.rb')
    end

    it 'deduplicates specs after stripping :line' do
      get_cmd = stub_open3

      # Two :line keys that refer to the same file
      described_class.run(specs: ['spec/a_spec.rb:1', 'spec/a_spec.rb:2'], parallel: true)

      cmd = get_cmd.call
      # spec/a_spec.rb should appear exactly once in the groups
      count = cmd.scan('spec/a_spec.rb').length
      expect(count).to eq(1)
    end

    it 'returns degraded_to_file_level: true' do
      stub_open3

      result = described_class.run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], parallel: true)

      expect(result[:degraded_to_file_level]).to be true
    end

    it 'includes the --require argument' do
      get_cmd = stub_open3

      described_class.run(specs: ['spec/a_spec.rb'], parallel: true)

      expect(get_cmd.call).to include("--require #{Testsort::Agent::SpecRunner::SPEC_HELPER_AGENT_PATH}")
    end
  end

  # -------------------------------------------------------------------------
  # Stale file cleanup
  # -------------------------------------------------------------------------

  describe 'stale glob cleanup' do
    it 'deletes stale result files before running the subprocess' do
      stale = ['testsort/agent_results.json', 'testsort/agent_results-env-2.json']
      call_order = []

      allow(Dir).to receive(:glob).with(Testsort::Paths.agent_results_glob).and_return(
        stale, ['testsort/agent_results.json']
      )
      allow(FileUtils).to receive(:rm_f) { |f| call_order << [:rm, f] }
      allow(Open3).to receive(:capture3) { |_cmd| call_order << [:open3]; ['', '', fake_status(0)] }

      described_class.run(specs: ['spec/foo_spec.rb'])

      rm_idx   = call_order.index { |e| e[0] == :rm }
      open_idx = call_order.index { |e| e[0] == :open3 }
      expect(rm_idx).to be < open_idx
    end
  end

  # -------------------------------------------------------------------------
  # Hard-error paths
  # -------------------------------------------------------------------------

  describe 'exit ≥ 2 → raises Testsort::Error' do
    it 'raises with stderr in the message when exit is 2' do
      allow(Dir).to receive(:glob).with(Testsort::Paths.agent_results_glob).and_return(
        [], []
      )
      stub_open3(stderr: 'LoadError: cannot load foo', exitstatus: 2)

      expect do
        described_class.run(specs: ['spec/foo_spec.rb'])
      end.to raise_error(Testsort::Error, /rspec did not produce results.*exit=2.*LoadError/)
    end

    it 'raises when no result files produced even on exit 0' do
      allow(Dir).to receive(:glob).with(Testsort::Paths.agent_results_glob).and_return(
        [], []
      )
      stub_open3(exitstatus: 0)

      expect do
        described_class.run(specs: ['spec/foo_spec.rb'])
      end.to raise_error(Testsort::Error, /rspec did not produce results/)
    end
  end

  # -------------------------------------------------------------------------
  # Happy path with results
  # -------------------------------------------------------------------------

  describe 'exit 0 or 1 with result files' do
    it 'calls ResultCollector.merge_files and returns examples' do
      stub_open3

      expect(Testsort::Agent::ResultCollector).to receive(:merge_files).and_return(default_merged)

      result = described_class.run(specs: ['spec/foo_spec.rb'])

      expect(result[:examples]).to eq(default_merged[:examples])
    end
  end
end

RSpec::Matchers.define :be_an_absolute_path do
  match { |actual| actual.to_s.start_with?('/') }
  failure_message { |actual| "expected #{actual.inspect} to be an absolute path" }
end
