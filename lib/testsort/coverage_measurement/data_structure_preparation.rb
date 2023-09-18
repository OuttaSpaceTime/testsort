module Testsort
  class CoverageMeasurement
    module DataStructurePreparation
      def add_code_file_to_index_mapping(covered_file)
        @code_file_to_index.insert(covered_file)
        @coverage_matrix.new_column(current_code_file_index, covered_spec_files_count)
      end

      def add_spec_file_to_index_mapping(spec)
        @spec_file_to_index.insert(spec)
        @coverage_matrix.new_row(current_spec_file_index, covered_codes_files_count)
      end

      def prepare_coverage_data_structures(spec_to_cover)
        code_files_to_index_mapping if @code_file_to_index.empty?

        @spec_file_to_index.insert(file_path(spec_to_cover))
        if @spec_file_to_index.has_new_entries
          @coverage_matrix.new_row(current_spec_file_index, covered_codes_files_count)
        end
      end

      def code_files_to_index_mapping
        coverage_result.each do |covered_file, _coverage_result_hash|
          @code_file_to_index.insert(Paths.relative_path_of(covered_file))
        end
      end

      def file_path(spec)
        if spec.file_path != spec.metadata[:rerun_file_path]
          spec.metadata[:rerun_file_path]
        else
          spec.file_path
        end
      end
    end
  end
end
