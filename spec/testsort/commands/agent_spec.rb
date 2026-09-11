# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

describe 'agent command' do
  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  def start(*args)
    Testsort::CLI.start(['agent'] + args)
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  def capture_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end

  def parse_json(str)
    JSON.parse(str, symbolize_names: true)
  end

  # Default fake Queries that returns a small universe/suggest
  def stub_queries(universe: ['spec/a_spec.rb:1', 'spec/b_spec.rb:1'], suggest_result: nil)
    suggest_result ||= universe
    queries_dbl = instance_double(
      Testsort::Agent::Queries,
      universe: universe,
      suggest:  suggest_result,
    )
    allow(Testsort::Agent::Queries).to receive(:new).and_return(queries_dbl)
    queries_dbl
  end

  def stub_spec_runner(examples: { 'spec/a_spec.rb:1' => { 'status' => 'passed' } }, exit_status: 0)
    result = { exit_status: exit_status, examples: examples, degraded_to_file_level: false }
    allow(Testsort::Agent::SpecRunner).to receive(:run).and_return(result)
    result
  end

  def stub_session
    session_dbl = instance_double(
      Testsort::Agent::Session,
      executed_set: Set.new,
      append_run:   nil,
    )
    allow(session_dbl).to receive(:append_run).and_return(session_dbl)
    allow(Testsort::Agent::Session).to receive(:load).and_return(session_dbl)
    session_dbl
  end

  # -------------------------------------------------------------------------
  # agent universe
  # -------------------------------------------------------------------------

  describe 'universe subcommand' do
    it 'outputs JSON with specs, count, and line_level' do
      stub_queries(universe: ['spec/a_spec.rb:1', 'spec/b_spec.rb:1'])

      out = capture_stdout { start('universe') }
      data = parse_json(out)

      expect(data[:specs]).to eq(['spec/a_spec.rb:1', 'spec/b_spec.rb:1'])
      expect(data[:count]).to eq(2)
      expect(data).to have_key(:line_level)
    end

    it 'outputs count matching specs length' do
      stub_queries(universe: ['spec/c_spec.rb'])

      out = capture_stdout { start('universe') }
      data = parse_json(out)

      expect(data[:count]).to eq(1)
    end

    context 'when Queries raises Testsort::Error (matrix not stored)' do
      it 'writes JSON error to stderr and exits 1' do
        allow(Testsort::Agent::Queries).to receive(:new)
          .and_raise(Testsort::Error, 'no coverage data found — run `testsort prepare` first')

        old_stderr = $stderr
        $stderr = StringIO.new
        expect { start('universe') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        stderr_out = $stderr.string
        $stderr = old_stderr

        data = JSON.parse(stderr_out, symbolize_names: true)
        expect(data[:error]).to match(/testsort prepare/)
      end
    end
  end

  # -------------------------------------------------------------------------
  # agent suggest
  # -------------------------------------------------------------------------

  describe 'suggest subcommand' do
    it 'defaults to absolute strategy and outputs JSON with specs/parallel/strategy' do
      stub_queries(suggest_result: ['spec/a_spec.rb:1', 'spec/b_spec.rb:1'])

      out = capture_stdout { start('suggest') }
      data = parse_json(out)

      expect(data[:specs]).to be_an(Array)
      expect(data[:parallel]).to be false
      expect(data[:strategy]).to eq('absolute')
    end

    it 'accepts a custom strategy name' do
      stub_queries(suggest_result: ['spec/a_spec.rb:1'])
      expect(Testsort::Agent::Queries).to receive(:new).with(strategy: 'additional').and_return(
        instance_double(Testsort::Agent::Queries, suggest: ['spec/a_spec.rb:1'], universe: [])
      )

      out = capture_stdout { start('suggest', 'additional') }
      data = parse_json(out)

      expect(data[:strategy]).to eq('additional')
    end

    it '--format=lines emits newline-delimited paths' do
      stub_queries(suggest_result: ['spec/a_spec.rb:1', 'spec/b_spec.rb:5'])

      out = capture_stdout { start('suggest', '--format=lines') }

      expect(out.split("\n")).to include('spec/a_spec.rb:1', 'spec/b_spec.rb:5')
    end

    it '--parallel with grouped result returns JSON with groups key' do
      groups = [['spec/a_spec.rb'], ['spec/b_spec.rb']]
      stub_queries(suggest_result: groups)

      allow_any_instance_of(Testsort::Agent::Queries).to receive(:suggest)
        .with(parallel: true)
        .and_return(groups)

      out = capture_stdout { start('suggest', '--parallel') }
      data = parse_json(out)

      expect(data[:groups]).to be_an(Array)
      expect(data[:parallel]).to be true
    end

    it '--format=lines with grouped result flattens into lines' do
      groups = [['spec/a_spec.rb'], ['spec/b_spec.rb']]
      stub_queries(suggest_result: groups)

      out = capture_stdout { start('suggest', '--format=lines') }
      lines = out.split("\n")

      expect(lines).to include('spec/a_spec.rb', 'spec/b_spec.rb')
    end

    context 'when Queries raises Testsort::Error' do
      it 'writes error JSON to stderr and exits 1' do
        allow(Testsort::Agent::Queries).to receive(:new)
          .and_raise(Testsort::Error, 'no coverage data found — run `testsort prepare` first')

        old_stderr = $stderr
        $stderr = StringIO.new
        expect { start('suggest') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        stderr_out = $stderr.string
        $stderr = old_stderr

        data = JSON.parse(stderr_out, symbolize_names: true)
        expect(data[:error]).not_to be_nil
      end
    end
  end

  # -------------------------------------------------------------------------
  # agent run
  # -------------------------------------------------------------------------

  describe 'run subcommand' do
    it 'calls SpecRunner.run, appends to session, outputs result JSON' do
      session = stub_session
      examples = { 'spec/a_spec.rb:1' => { 'status' => 'passed', 'duration' => 0.1 } }
      stub_spec_runner(examples: examples, exit_status: 0)

      out = capture_stdout { start('run', 'spec/a_spec.rb:1') }
      data = parse_json(out)

      expect(data[:ran_count]).to eq(1)
      expect(data[:exit_status]).to eq(0)
      expect(data).to have_key(:examples)
      expect(Testsort::Agent::SpecRunner).to have_received(:run).with(
        specs: ['spec/a_spec.rb:1'], parallel: false
      )
      expect(session).to have_received(:append_run)
    end

    it '--from-stdin reads spec paths from $stdin' do
      session = stub_session
      stub_spec_runner

      fake_stdin = StringIO.new("spec/foo_spec.rb\nspec/bar_spec.rb\n")
      allow($stdin).to receive(:read).and_return(fake_stdin.read)

      out = capture_stdout { start('run', '--from-stdin') }
      data = parse_json(out)

      expect(data[:ran_count]).to be >= 0
      expect(Testsort::Agent::SpecRunner).to have_received(:run).with(
        specs: ['spec/foo_spec.rb', 'spec/bar_spec.rb'], parallel: false
      )
    end

    it 'raises error when no specs and no stdin' do
      old_stderr = $stderr
      $stderr = StringIO.new
      expect { start('run') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      stderr_out = $stderr.string
      $stderr = old_stderr

      data = JSON.parse(stderr_out, symbolize_names: true)
      expect(data[:error]).to match(/no specs provided/)
    end

    context 'when SpecRunner raises Testsort::Error' do
      it 'writes error JSON to stderr and exits 1' do
        stub_session
        allow(Testsort::Agent::SpecRunner).to receive(:run)
          .and_raise(Testsort::Error, 'rspec did not produce results: exit=2')

        old_stderr = $stderr
        $stderr = StringIO.new
        expect { start('run', 'spec/a_spec.rb') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        stderr_out = $stderr.string
        $stderr = old_stderr

        data = JSON.parse(stderr_out, symbolize_names: true)
        expect(data[:error]).to match(/rspec did not produce results/)
      end
    end
  end

  # -------------------------------------------------------------------------
  # agent run-floor
  # -------------------------------------------------------------------------

  describe 'run-floor subcommand' do
    it 'returns floor_satisfied: true, ran_count: 0 when no specs remain' do
      stub_queries(universe: ['spec/a_spec.rb:1'])
      session = stub_session
      allow(session).to receive(:executed_set).and_return(Set.new(['spec/a_spec.rb:1']))

      out = capture_stdout { start('run-floor') }
      data = parse_json(out)

      expect(data[:floor_satisfied]).to be true
      expect(data[:ran_count]).to eq(0)
    end

    it 'runs remaining specs and appends to session when universe not fully executed' do
      stub_queries(universe: ['spec/a_spec.rb:1', 'spec/b_spec.rb:1'])
      session = stub_session
      allow(session).to receive(:executed_set).and_return(Set.new(['spec/a_spec.rb:1']))
      examples = { 'spec/b_spec.rb:1' => { 'status' => 'passed' } }
      stub_spec_runner(examples: examples, exit_status: 0)

      out = capture_stdout { start('run-floor') }
      data = parse_json(out)

      expect(data[:floor_satisfied]).to be true
      expect(data[:ran_count]).to eq(1)
      expect(Testsort::Agent::SpecRunner).to have_received(:run).with(
        specs: ['spec/b_spec.rb:1'], parallel: false
      )
      expect(session).to have_received(:append_run)
    end

    context 'when Queries raises Testsort::Error' do
      it 'writes error JSON to stderr and exits 1' do
        allow(Testsort::Agent::Queries).to receive(:new)
          .and_raise(Testsort::Error, 'no coverage data found')

        old_stderr = $stderr
        $stderr = StringIO.new
        expect { start('run-floor') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        stderr_out = $stderr.string
        $stderr = old_stderr

        data = JSON.parse(stderr_out, symbolize_names: true)
        expect(data[:error]).not_to be_nil
      end
    end
  end
end
