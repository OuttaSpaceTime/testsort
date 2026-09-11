# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module Testsort
  module Agent
    # RSpec listener that records per-example results to JSON.
    # Mirrors the shape of Testsort::Evaluation::TestsuiteEvaluation.
    #
    # Do NOT register this listener at file load. The spec_helper_agent.rb
    # file does that wiring for direct `agent run`/`agent run-floor` invocations.
    class ResultListener
      def initialize
        @examples = {}
      end

      def example_finished(notification)
        example          = notification.example
        execution_result = example.execution_result
        exc              = execution_result.exception

        file = example.file_path.delete_prefix('./')
        line = example.metadata[:line_number]
        key  = "#{file}:#{line}"

        @examples[key] = {
          key: key,
          file: file,
          line: line,
          status: execution_result.status,
          duration: execution_result.run_time,
          exception_message: exc&.message,
          exception_backtrace: exc&.backtrace&.first(5)
        }
      end

      def flush
        path = Testsort::Paths.agent_results_path(test_env_number)
        dir  = File.dirname(path)
        FileUtils.mkdir_p(dir)

        Testsort::IOHelper.exclusively_locked_dir_access(dir) do
          payload = {
            generated_at: Time.now.utc.iso8601,
            examples: @examples
          }
          File.open(path, 'w+') do |f|
            f.puts JSON.pretty_generate(payload)
          end
        end
      end

      private

      def test_env_number
        val = ENV['TEST_ENV_NUMBER']
        return nil if val.nil? || val.empty?

        val
      end
    end
  end
end
