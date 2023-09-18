module Testsort
  class Prioritization
    delegate :coverage_matrix, :code_file_to_index, :spec_file_to_index, to: :@coverage_measurement

    def initialize(changeset, coverage_measurement)
      @changeset = changeset
      @coverage_measurement = coverage_measurement
      @spec_list = SpecList.new(spec_file_to_index.file_list)
    end

    def prioritized_spec_order(in_groups: false)
      raise NoMethodError
    end

    def spec_count
      spec_file_to_index&.count || 0
    end

    def affected_file_indices
      files_to_prioritize = @changeset.affected
      files_to_prioritize.map { |file| code_file_to_index[file] }.compact
    end

    def coverage_matrix_slice(by_specs: false)
      @coverage_matrix_narray ||= coverage_matrix.slice_by_files(affected_file_indices, by_specs: by_specs)
    end
  end
end
