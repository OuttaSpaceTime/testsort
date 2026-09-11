# frozen_string_literal: true

require 'set'

module Testsort
  module Agent
    class Session
      VERSION = 1

      attr_reader :path

      # Load (or create) a session from Paths::AGENT_SESSION.
      # Creates an empty session file at that path if it does not exist.
      #
      # @return [Session]
      def self.load(path = Paths::AGENT_SESSION)
        new(path).tap(&:load_or_create)
      end

      def initialize(path = Paths::AGENT_SESSION)
        @path = path
        @data = empty_data
      end

      # Load from file, creating an empty session if the file does not exist.
      def load_or_create
        raw = File.exist?(@path) ? File.read(@path) : nil
      if raw && !raw.strip.empty?
          @data = JSON.parse(raw)
        else
          FileUtils.mkdir_p(File.dirname(@path))
          persist
        end
        self
      end

      # Append a run to the session and persist to disk.
      #
      # @param specs [Array<String>] the spec keys that were run.
      # @param results [Hash] key => {status:, duration:, ...} result data.
      def append_run(specs:, results:)
        run_entry = {
          'at'      => Time.now.utc.iso8601,
          'specs'   => specs,
          'results' => results,
        }
        @data['runs'] << run_entry

        # Merge specs into top-level executed array (dedup)
        existing = @data['executed'].to_set
        specs.each { |s| existing.add(s) }
        @data['executed'] = existing.to_a

        persist
        self
      end

      # Returns a Set of all spec keys that have been executed in this session.
      #
      # @return [Set<String>]
      def executed_set
        Set.new(@data['executed'] || [])
      end

      # Returns the raw runs array.
      #
      # @return [Array<Hash>]
      def runs
        @data['runs'] || []
      end

      # Clears the session file (used by tests and possibly future CLI).
      def reset!
        @data = empty_data
        persist
        self
      end

      private

      def empty_data
        {
          'version'    => VERSION,
          'started_at' => Time.now.utc.iso8601,
          'executed'   => [],
          'runs'       => [],
        }
      end

      def persist
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(@data))
      end
    end
  end
end
