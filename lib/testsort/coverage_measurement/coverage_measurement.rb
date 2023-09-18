# frozen_string_literal: true
require_relative 'storage/serializer'
require_relative 'data_structure_preparation'

module Testsort
  class CoverageMeasurement
    require 'coverage'

    include CoverageMeasurement::DataStructurePreparation
    include CoverageMeasurement::Storage::Serializer

    attr_reader :coverage_matrix, :code_file_to_index, :spec_file_to_index

    delegate :file_index, to: :@code_file_to_index, prefix: :current_code
    delegate :file_index, to: :@spec_file_to_index, prefix: :current_spec
    delegate :count, to: :@code_file_to_index, prefix: :covered_codes_files
    delegate :count, to: :@spec_file_to_index, prefix: :covered_spec_files

    def initialize(options = { from_disk: false, path: nil })
      if options[:from_disk]
        return unless Paths.last_run_stored?

        deserialize(options)
      else
        @code_file_to_index = FileToIndexMapping.new
        @spec_file_to_index = FileToIndexMapping.new
        @coverage_matrix = CoverageMatrix.new
      end
    end

    def start
      Coverage.result(stop: true, clear: true) if Coverage.running?

      Coverage.start(Testsort.configuration.coverage_mode)
    end

    def finish
      if Paths.last_run_stored?
        merge_results_from_previous_run
      end

      serialize
    end

    def cover(spec_to_cover)
      # Coverage.start(Testsort.configuration.coverage_mode) unless Coverage.running?

      raise Testsort::Error::CoverageNotStarted, 'Coverage measurement was not started' unless Coverage.running?

      prepare_coverage_data_structures(spec_to_cover)
      process_coverage_result
    end

    private

    def process_coverage_result
      coverage_result.each do |covered_file, coverage_result|
        covered_file = Paths.relative_path_of(covered_file)
        add_code_file_to_index_mapping(covered_file) if @code_file_to_index.exclude?(covered_file)

        @coverage_matrix[current_spec_file_index, @code_file_to_index[covered_file]] += times_hit(coverage_result)
      end

      @coverage_result = nil
    end

    def coverage_result
      @coverage_result ||= ::Coverage.result(clear: true).select do |file_path, _coverage|
        file_path =~ Paths.project_root_path_regex # && file_path.exclude?('spec')
      end
    end

    def times_hit(coverage_result)
      if coverage_result.instance_of?(Hash)
        covered_lines_array =
          if Testsort.configuration.lines
            coverage_result[:lines]
          elsif Testsort.configuration.oneshot_lines
            coverage_result[:oneshot_lines]&.map { 1 } || []
          end
      elsif coverage_result.instance_of?(Array)
        covered_lines_array = coverage_result
      end

      covered_lines_array.compact.sum
    end

    def merge_results_from_previous_run
      coverage_measurement = CoverageMeasurement.new(from_disk: true)
      result_merger = CoverageMeasurement::Storage::TestrunMerger.new(coverage_measurement, self)
      merged_measurement = result_merger.merge_coverage_results
      merged_measurement.instance_variables.each do |attribute|
        instance_variable_set(attribute, merged_measurement.instance_variable_get(attribute))
      end
    end
  end
end
