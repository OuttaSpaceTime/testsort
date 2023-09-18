module Testsort
  class CoverageMeasurement
    module Storage
      class TestrunMerger

        delegate :coverage_matrix, :code_file_to_index, :spec_file_to_index, to: :@ground_truth_coverage, prefix: :ground_truth
        delegate :coverage_matrix, :code_file_to_index, :spec_file_to_index, to: :@new_coverage_measurement, prefix: :new

        def initialize(ground_truth_coverage_measurement, new_coverage_measurement)
          @ground_truth_coverage = ground_truth_coverage_measurement
          @new_coverage_measurement = new_coverage_measurement
        end

        def merge_coverage_results
          (0..new_coverage_matrix.shape[0] - 1).each do |new_spec_index|
            (0..new_coverage_matrix.shape[1] - 1).each do |new_file_index|
              current_file_path = new_code_file_to_index[new_file_index]
              current_spec_path = new_spec_file_to_index[new_spec_index]

              new_ground_truth_entries_by_case(current_file_path, current_spec_path)
              set_ground_truth_coverage(current_file_path, current_spec_path, new_file_index, new_spec_index)
            end
          end
          @ground_truth_coverage
        end

        def new_ground_truth_entries_by_case(current_file_path, current_spec_path)
          if file_not_covered?(current_file_path)
            @ground_truth_coverage.add_code_file_to_index_mapping(current_file_path)
          end
          if spec_not_covered?(current_spec_path)
            @ground_truth_coverage.add_spec_file_to_index_mapping(current_spec_path)
          end
        end

        def spec_not_covered?(spec_path)
          ground_truth_spec_file_to_index.exclude?(spec_path)
        end

        def file_not_covered?(file_path)
          ground_truth_code_file_to_index.exclude?(file_path)
        end

        def set_ground_truth_coverage(file_path, spec_path, new_file_index, new_spec_index)
          ground_truth_coverage_matrix[ground_truth_spec_file_to_index[spec_path],
                                       ground_truth_code_file_to_index[file_path]] =
            new_coverage_matrix[new_spec_index, new_file_index]
        end
      end
    end
  end
end
