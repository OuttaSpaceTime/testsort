# frozen_string_literal: true

require 'json'
require 'fileutils'

module Testsort
  module Agent
    # Pure file-merge logic: reads all per-worker agent_results*.json files,
    # unions the examples hashes, and deletes the per-env files after a
    # successful merge.
    #
    # Mirrors the shape of Testsort::Evaluation::ExceptionTracker.merge_files.
    module ResultCollector
      class << self
        # Globs Paths.agent_results_glob, parses each per-env JSON, unions the
        # examples hashes (later writes win on key conflict; in practice keys
        # are unique per file:line). After successful merge, deletes the per-env
        # files. Returns a hash: { generated_at: String|nil, examples: {} }.
        def merge_files
          paths = Dir.glob(Testsort::Paths.agent_results_glob).sort

          return { generated_at: nil, examples: {} } if paths.empty?

          merged_examples = {}
          last_generated_at = nil

          paths.each do |path|
            raw = File.read(path)
            begin
              data = JSON.parse(raw)
            rescue JSON::ParserError => e
              raise Testsort::Error, "Failed to parse agent results file #{path}: #{e.message}"
            end

            last_generated_at = data['generated_at'] if data['generated_at']
            examples = data['examples'] || {}
            merged_examples.merge!(examples)
          end

          # Delete per-env files only after successful merge
          paths.each { |p| FileUtils.rm_f(p) }

          { generated_at: last_generated_at, examples: merged_examples }
        end
      end
    end
  end
end
