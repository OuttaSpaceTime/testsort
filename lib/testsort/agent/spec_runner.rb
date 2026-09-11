# frozen_string_literal: true

require 'open3'
require 'etc'

module Testsort
  module Agent
    # Runs a batch of specs in a subprocess (serial or parallel) and returns
    # per-example results via ResultCollector.
    #
    # Class method +SpecRunner.run(specs:, parallel:)+ → Hash:
    #   {
    #     exit_status:          Integer,
    #     examples:             Hash,  # key => {status:, duration:, ...}
    #     degraded_to_file_level: Boolean,
    #   }
    module SpecRunner
      SPEC_HELPER_AGENT_PATH = File.expand_path('../spec_helper_agent.rb', __FILE__).freeze

      class << self
        # @param specs [Array<String>] spec keys to run (path or path:line).
        # @param parallel [Boolean|truthy] when truthy use parallel_rspec.
        # @return [Hash] exit_status:, examples:, degraded_to_file_level:
        def run(specs:, parallel: false)
          raise Testsort::Error, 'no specs provided' if specs.nil? || specs.empty?

          # Filter to in-project spec/ paths (drop shared_examples, gem paths)
          in_project = ->(key) { key.start_with?('spec/', './spec/') }
          filtered = specs.select(&in_project)
          filtered = filtered.reject { |k| k.include?('shared_examples') }

          raise Testsort::Error, 'no specs provided' if filtered.empty?

          # Clean up stale results from previous runs
          Dir.glob(Testsort::Paths.agent_results_glob).each { |f| FileUtils.rm_f(f) }

          if parallel
            command = build_parallel_command(filtered)
            degraded = true
          else
            command = build_serial_command(filtered)
            degraded = false
          end

          stdout, stderr, status = Bundler.with_unbundled_env do
            Open3.capture3(command)
          end

          $stdout.print stdout
          $stderr.print stderr

          # Exit ≥ 2 or no result files → hard error
          if status.exitstatus >= 2 || Dir.glob(Testsort::Paths.agent_results_glob).empty?
            truncated_stderr = stderr.to_s[0, 2000]
            raise Testsort::Error,
              "rspec did not produce results: exit=#{status.exitstatus}, stderr=#{truncated_stderr}"
          end

          merged = Testsort::Agent::ResultCollector.merge_files

          {
            exit_status:            status.exitstatus,
            examples:               merged.fetch(:examples),
            degraded_to_file_level: degraded,
          }
        end

        private

        def build_serial_command(specs)
          parts = [
            'bundle exec rspec',
            "--require #{SPEC_HELPER_AGENT_PATH}",
            '--no-color',
            '--order defined',
          ]
          parts.concat(specs)
          parts.join(' ')
        end

        def build_parallel_command(specs)
          # Strip :line suffixes for parallel_rspec compatibility
          file_specs = specs.map { |k| k.split(':').first }.uniq

          # Round-robin grouping
          n = (ENV['PARALLEL_TEST_PROCESSORS']&.to_i || Etc.nprocessors).clamp(1, Float::INFINITY)
          groups = Array.new(n) { [] }
          file_specs.each_with_index { |s, i| groups[i % n] << s }
          groups.reject!(&:empty?)

          group_str = groups.map { |g| g.join(',') }.join('|')

          [
            'bundle exec parallel_rspec',
            "--require #{SPEC_HELPER_AGENT_PATH}",
            "-n #{groups.size}",
            "--specify-groups '#{group_str}'",
          ].join(' ')
        end
      end
    end
  end
end
