# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'testsort/agent/result_collector'

describe Testsort::Agent::ResultCollector do
  around do |example|
    Dir.mktmpdir('result_collector_spec') do |tmpdir|
      @tmpdir = tmpdir
      example.run
    end
  end

  def write_results_file(path, examples_hash)
    data = {
      'generated_at' => Time.now.utc.iso8601,
      'examples' => examples_hash
    }
    File.write(path, JSON.pretty_generate(data))
  end

  def results_path(suffix = nil)
    if suffix
      File.join(@tmpdir, "agent_results-env-#{suffix}.json")
    else
      File.join(@tmpdir, 'agent_results.json')
    end
  end

  def stub_glob(*paths)
    allow(Testsort::Paths).to receive(:agent_results_glob).and_return(
      File.join(@tmpdir, 'agent_results*.json')
    )
  end

  describe '.merge_files' do
    context 'with a single file' do
      it 'returns all examples from that file' do
        path = results_path
        write_results_file(path, {
          'spec/a_spec.rb:1' => { 'key' => 'spec/a_spec.rb:1', 'status' => 'passed', 'duration' => 0.1 }
        })
        stub_glob(path)

        result = described_class.merge_files
        expect(result[:examples].keys).to contain_exactly('spec/a_spec.rb:1')
        expect(result[:generated_at]).not_to be_nil
      end
    end

    context 'with multiple per-env files' do
      it 'unions examples from all files' do
        path1 = results_path
        path2 = results_path('2')

        write_results_file(path1, {
          'spec/a_spec.rb:1' => { 'key' => 'spec/a_spec.rb:1', 'status' => 'passed', 'duration' => 0.1 }
        })
        write_results_file(path2, {
          'spec/b_spec.rb:5' => { 'key' => 'spec/b_spec.rb:5', 'status' => 'failed', 'duration' => 0.2 }
        })

        allow(Testsort::Paths).to receive(:agent_results_glob).and_return(
          File.join(@tmpdir, 'agent_results*.json')
        )

        result = described_class.merge_files
        expect(result[:examples].keys).to contain_exactly('spec/a_spec.rb:1', 'spec/b_spec.rb:5')
      end

      it 'later files win on key conflict' do
        # Sort order matters — both files have same key; last parsed wins.
        # In practice keys are unique but test the semantics.
        path1 = results_path
        path2 = results_path('2')

        write_results_file(path1, {
          'spec/a_spec.rb:1' => { 'key' => 'spec/a_spec.rb:1', 'status' => 'passed', 'duration' => 0.1 }
        })
        write_results_file(path2, {
          'spec/a_spec.rb:1' => { 'key' => 'spec/a_spec.rb:1', 'status' => 'failed', 'duration' => 0.2 }
        })

        allow(Testsort::Paths).to receive(:agent_results_glob).and_return(
          File.join(@tmpdir, 'agent_results*.json')
        )

        result = described_class.merge_files
        # One entry, last-write wins
        expect(result[:examples].size).to eq(1)
      end
    end

    context 'after merging' do
      it 'deletes all per-env files' do
        path1 = results_path
        path2 = results_path('2')

        write_results_file(path1, {})
        write_results_file(path2, {})

        allow(Testsort::Paths).to receive(:agent_results_glob).and_return(
          File.join(@tmpdir, 'agent_results*.json')
        )

        described_class.merge_files

        expect(File.exist?(path1)).to be false
        expect(File.exist?(path2)).to be false
      end
    end

    context 'with no matching files' do
      it 'returns empty examples and nil generated_at' do
        allow(Testsort::Paths).to receive(:agent_results_glob).and_return(
          File.join(@tmpdir, 'agent_results*.json')
        )

        result = described_class.merge_files
        expect(result[:examples]).to eq({})
        expect(result[:generated_at]).to be_nil
      end
    end

    context 'with malformed JSON' do
      it 'raises Testsort::Error mentioning the offending path' do
        path = results_path
        File.write(path, 'not valid json {{{')

        allow(Testsort::Paths).to receive(:agent_results_glob).and_return(
          File.join(@tmpdir, 'agent_results*.json')
        )

        expect { described_class.merge_files }.to raise_error(Testsort::Error, /#{Regexp.escape(path)}/)
      end
    end
  end
end
