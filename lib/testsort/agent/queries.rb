# frozen_string_literal: true

module Testsort
  module Agent
    class Queries
      STRATEGY_MAP = {
        'absolute'          => -> { Testsort::Prioritization::Strategies::Absolute },
        'oneshot'           => -> { Testsort::Prioritization::Strategies::Absolute },
        'additional'        => -> { Testsort::Prioritization::Strategies::Additional },
        'additional pseudo' => -> { Testsort::Prioritization::Strategies::AdditionalPseudo },
        'additional_pseudo' => -> { Testsort::Prioritization::Strategies::AdditionalPseudo },
      }.freeze

      # Resolve a strategy name string to a Prioritization strategy class.
      # Raises Testsort::Error for unknown strategies.
      def self.strategy_class_for(name)
        normalized = name.to_s.strip.downcase.gsub('_', ' ')
        klass_proc = STRATEGY_MAP[normalized] || STRATEGY_MAP[normalized.gsub(' ', '_')]
        unless klass_proc
          raise Testsort::Error, "Unknown strategy '#{name}'. Valid strategies: absolute, oneshot, additional, additional_pseudo"
        end

        klass_proc.call
      end

      # @param coverage_measurement [CoverageMeasurement, nil] If nil, loads from disk.
      # @param changeset [Changeset, nil] If nil, creates a new Changeset.
      # @param strategy [String] Strategy name for #suggest.
      def initialize(coverage_measurement: nil, changeset: nil, strategy: 'absolute')
        unless Paths.last_run_stored?
          raise Testsort::Error, "no coverage data found — run `testsort prepare` first"
        end

        @coverage_measurement = coverage_measurement || CoverageMeasurement.new(from_disk: true)
        @changeset = changeset || Changeset.new
        @strategy = strategy
      end

      # Returns the set of spec keys relevant to the current diff.
      #
      # In line_level mode: path:line keys.
      # In file_level mode: plain spec file paths.
      #
      # Order: matrix-matched specs first (by strategy priority), then new spec
      # files from the diff that have no matrix row.
      #
      # @return [Array<String>]
      def universe
        matched = matched_spec_keys
        new_specs = new_spec_files_from_diff

        # Exclude new_specs already in matched (dedup)
        matched_set = matched.to_set
        extra = new_specs.reject { |s| matched_set.include?(s) }

        matched + extra
      end

      # Returns the prioritized spec ordering produced by the chosen strategy.
      #
      # @param parallel [Boolean] When true, returns Array<Array<String>> (groups);
      #   when false, returns Array<String>.
      # @return [Array<String> | Array<Array<String>>]
      def suggest(parallel: false)
        prioritization.prioritized_spec_order(in_groups: parallel)
      end

      private

      def prioritization
        @prioritization ||= begin
          klass = self.class.strategy_class_for(@strategy)
          klass.new(@changeset, @coverage_measurement)
        end
      end

      # Returns matched spec keys from the coverage matrix for affected files.
      #
      # Line-level mode: uses affected_example_indices (returns spec indices),
      #   maps via spec_file_to_index.fetch_specs.
      # File-level mode: iterates spec indices and checks coverage for each
      #   affected file index.
      def matched_spec_keys
        if Testsort.configuration.line_level
          indices = prioritization.affected_example_indices
          return [] if indices.empty?

          @coverage_measurement.spec_file_to_index.fetch_specs(indices.map(&:to_s))
        else
          affected_idxs = prioritization.affected_file_indices
          return [] if affected_idxs.empty?

          spec_mapping = @coverage_measurement.spec_file_to_index
          coverage_matrix = @coverage_measurement.coverage_matrix

          spec_mapping.path_hash.each_with_object([]) do |(spec_path, spec_idx), result|
            if affected_idxs.any? { |file_idx| coverage_matrix[spec_idx, file_idx] > 0 }
              result << spec_path
            end
          end
        end
      end

      # Returns new spec files from the diff that are not already in the matrix.
      def new_spec_files_from_diff
        spec_mapping = @coverage_measurement.spec_file_to_index

        @changeset.affected.select do |path|
          path.start_with?('spec/') && path.end_with?('_spec.rb') && spec_mapping.exclude?(path)
        end
      end
    end
  end
end
