# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'testsort/agent/result_listener'

describe Testsort::Agent::ResultListener do
  around do |example|
    Dir.mktmpdir('result_listener_spec') do |tmpdir|
      @tmpdir = tmpdir
      example.run
    end
  end

  def make_notification(file_path:, line_number:, status:, run_time: 0.1, exception: nil)
    execution_result = instance_double(
      'RSpec::Core::Example::ExecutionResult',
      status: status,
      run_time: run_time,
      exception: exception
    )
    example = instance_double(
      'RSpec::Core::Example',
      file_path: file_path,
      metadata: { line_number: line_number },
      execution_result: execution_result
    )
    instance_double('RSpec::Core::Notifications::ExampleNotification', example: example)
  end

  shared_examples 'writes correct JSON' do |env_suffix: nil|
    it 'writes a JSON file with the correct shape' do
      notification = make_notification(
        file_path: './spec/foo_spec.rb',
        line_number: 42,
        status: :passed,
        run_time: 0.123
      )

      results_path = if env_suffix
        File.join(@tmpdir, "agent_results-env-#{env_suffix}.json")
      else
        File.join(@tmpdir, 'agent_results.json')
      end

      allow(Testsort::Paths).to receive(:agent_results_path).with(env_suffix).and_return(results_path)
      FileUtils.mkdir_p(@tmpdir)

      listener = described_class.new
      listener.example_finished(notification)
      listener.flush

      expect(File.exist?(results_path)).to be true

      data = JSON.parse(File.read(results_path))
      expect(data['generated_at']).not_to be_nil
      expect(data['examples']).to be_a(Hash)

      key = 'spec/foo_spec.rb:42'
      entry = data['examples'][key]
      expect(entry).not_to be_nil
      expect(entry['key']).to eq(key)
      expect(entry['file']).to eq('spec/foo_spec.rb')
      expect(entry['line']).to eq(42)
      expect(entry['status']).to eq('passed')
      expect(entry['duration']).to be_within(0.001).of(0.123)
      expect(entry['exception_message']).to be_nil
      expect(entry['exception_backtrace']).to be_nil
    end
  end

  context 'without TEST_ENV_NUMBER' do
    before { ENV.delete('TEST_ENV_NUMBER') }

    include_examples 'writes correct JSON', env_suffix: nil
  end

  context 'with TEST_ENV_NUMBER=2' do
    around do |example|
      old = ENV['TEST_ENV_NUMBER']
      ENV['TEST_ENV_NUMBER'] = '2'
      example.run
    ensure
      ENV['TEST_ENV_NUMBER'] = old
    end

    include_examples 'writes correct JSON', env_suffix: '2'
  end

  context 'with TEST_ENV_NUMBER empty string (worker 1 / serial)' do
    around do |example|
      old = ENV['TEST_ENV_NUMBER']
      ENV['TEST_ENV_NUMBER'] = ''
      example.run
    ensure
      ENV['TEST_ENV_NUMBER'] = old
    end

    include_examples 'writes correct JSON', env_suffix: nil
  end

  describe '#example_finished' do
    it 'strips leading ./ from file path when building key and file field' do
      notification = make_notification(
        file_path: './spec/bar_spec.rb',
        line_number: 10,
        status: :passed
      )
      results_path = File.join(@tmpdir, 'agent_results.json')
      allow(Testsort::Paths).to receive(:agent_results_path).with(nil).and_return(results_path)
      ENV.delete('TEST_ENV_NUMBER')
      FileUtils.mkdir_p(@tmpdir)

      listener = described_class.new
      listener.example_finished(notification)
      listener.flush

      data = JSON.parse(File.read(results_path))
      expect(data['examples'].key?('spec/bar_spec.rb:10')).to be true
      expect(data['examples']['spec/bar_spec.rb:10']['file']).to eq('spec/bar_spec.rb')
    end
  end

  describe 'failed example with exception' do
    it 'captures exception_message and exception_backtrace' do
      backtrace = ['spec/foo_spec.rb:42', 'spec/support/helper.rb:5', 'lib/thing.rb:10',
                   'lib/other.rb:20', 'lib/more.rb:30', 'lib/extra.rb:1']
      exception = instance_double(
        'RuntimeError',
        message: 'something went wrong',
        backtrace: backtrace
      )
      notification = make_notification(
        file_path: './spec/foo_spec.rb',
        line_number: 42,
        status: :failed,
        run_time: 0.05,
        exception: exception
      )

      results_path = File.join(@tmpdir, 'agent_results.json')
      allow(Testsort::Paths).to receive(:agent_results_path).with(nil).and_return(results_path)
      ENV.delete('TEST_ENV_NUMBER')
      FileUtils.mkdir_p(@tmpdir)

      listener = described_class.new
      listener.example_finished(notification)
      listener.flush

      data = JSON.parse(File.read(results_path))
      entry = data['examples']['spec/foo_spec.rb:42']
      expect(entry['status']).to eq('failed')
      expect(entry['exception_message']).to eq('something went wrong')
      expect(entry['exception_backtrace']).to eq(backtrace.first(5))
    end
  end

  describe '#flush' do
    it 'records multiple examples in the same flush' do
      results_path = File.join(@tmpdir, 'agent_results.json')
      allow(Testsort::Paths).to receive(:agent_results_path).with(nil).and_return(results_path)
      ENV.delete('TEST_ENV_NUMBER')
      FileUtils.mkdir_p(@tmpdir)

      listener = described_class.new

      [['./spec/a_spec.rb', 1], ['./spec/b_spec.rb', 2]].each do |file, line|
        n = make_notification(file_path: file, line_number: line, status: :passed)
        listener.example_finished(n)
      end

      listener.flush

      data = JSON.parse(File.read(results_path))
      expect(data['examples'].keys).to contain_exactly('spec/a_spec.rb:1', 'spec/b_spec.rb:2')
    end
  end
end
