# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'tempfile'

describe Testsort::Agent::Session do
  # Use a Tempfile so each test gets an isolated file and never touches the
  # real project's testsort/ storage directory.
  let(:tmpfile) { Tempfile.new(['agent_session', '.json']) }
  let(:session_path) { tmpfile.path }

  after do
    tmpfile.close
    tmpfile.unlink
  end

  def load_session(path = session_path)
    # Session.load creates the file if absent; use a temp path.
    described_class.load(path)
  end

  # -------------------------------------------------------------------------
  # Empty session creation
  # -------------------------------------------------------------------------
  describe '.load' do
    it 'creates a session when the file does not exist (new path)' do
      new_path = File.join(Dir.tmpdir, "agent_session_#{Process.pid}_#{rand(100_000)}.json")
      begin
        session = described_class.load(new_path)
        expect(File.exist?(new_path)).to be true
        expect(session.executed_set).to be_empty
        expect(session.runs).to be_empty
      ensure
        FileUtils.rm_f(new_path)
      end
    end

    it 'loads an existing session file' do
      # First create a session and add a run, then reload it.
      s1 = load_session
      s1.append_run(specs: ['spec/foo_spec.rb'], results: { 'spec/foo_spec.rb' => { 'status' => 'passed' } })

      s2 = load_session
      expect(s2.executed_set).to include('spec/foo_spec.rb')
      expect(s2.runs.length).to eq(1)
    end

    it 'persists "version" in the JSON file' do
      load_session
      data = JSON.parse(File.read(session_path))
      expect(data['version']).to eq(1)
    end

    it 'persists "started_at" as an ISO 8601 string' do
      load_session
      data = JSON.parse(File.read(session_path))
      expect(data['started_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
    end
  end

  # -------------------------------------------------------------------------
  # #append_run
  # -------------------------------------------------------------------------
  describe '#append_run' do
    it 'appends to the runs array' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb'], results: {})
      session.append_run(specs: ['spec/b_spec.rb'], results: {})

      expect(session.runs.length).to eq(2)
    end

    it 'merges specs into executed (union)' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], results: {})

      expect(session.executed_set).to include('spec/a_spec.rb', 'spec/b_spec.rb')
    end

    it 'deduplicates executed specs across multiple runs' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb'], results: {})
      session.append_run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], results: {})

      expect(session.executed_set.to_a.count('spec/a_spec.rb')).to eq(1)
    end

    it 'records the "at" timestamp in each run' do
      session = load_session
      session.append_run(specs: ['spec/x_spec.rb'], results: {})

      run = session.runs.first
      expect(run['at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
    end

    it 'persists the run data to disk' do
      session = load_session
      results = { 'spec/foo_spec.rb' => { 'status' => 'passed', 'duration' => 0.5 } }
      session.append_run(specs: ['spec/foo_spec.rb'], results: results)

      reloaded = load_session
      expect(reloaded.runs.length).to eq(1)
      expect(reloaded.runs.first['specs']).to eq(['spec/foo_spec.rb'])
      expect(reloaded.runs.first['results']).to eq({ 'spec/foo_spec.rb' => { 'status' => 'passed', 'duration' => 0.5 } })
    end

    it 'round-trips multiple runs with deduped executed list' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb'], results: { 'spec/a_spec.rb' => { 'status' => 'passed' } })
      session.append_run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], results: { 'spec/b_spec.rb' => { 'status' => 'failed' } })

      reloaded = load_session
      expect(reloaded.executed_set).to contain_exactly('spec/a_spec.rb', 'spec/b_spec.rb')
      expect(reloaded.runs.length).to eq(2)
    end
  end

  # -------------------------------------------------------------------------
  # #executed_set
  # -------------------------------------------------------------------------
  describe '#executed_set' do
    it 'returns a Set' do
      session = load_session
      expect(session.executed_set).to be_a(Set)
    end

    it 'returns empty Set for a fresh session' do
      session = load_session
      expect(session.executed_set).to be_empty
    end

    it 'returns a Set containing all previously executed specs' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb', 'spec/b_spec.rb'], results: {})
      session.append_run(specs: ['spec/c_spec.rb'], results: {})

      expect(session.executed_set).to eq(Set.new(['spec/a_spec.rb', 'spec/b_spec.rb', 'spec/c_spec.rb']))
    end
  end

  # -------------------------------------------------------------------------
  # #reset!
  # -------------------------------------------------------------------------
  describe '#reset!' do
    it 'clears executed and runs' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb'], results: {})
      session.reset!

      expect(session.executed_set).to be_empty
      expect(session.runs).to be_empty
    end

    it 'persists the empty state to disk' do
      session = load_session
      session.append_run(specs: ['spec/a_spec.rb'], results: {})
      session.reset!

      reloaded = load_session
      expect(reloaded.executed_set).to be_empty
      expect(reloaded.runs).to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # #path
  # -------------------------------------------------------------------------
  describe '#path' do
    it 'returns the configured path' do
      session = described_class.new(session_path)
      expect(session.path).to eq(session_path)
    end
  end
end
