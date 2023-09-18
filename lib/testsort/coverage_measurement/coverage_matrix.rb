module Testsort
  class CoverageMeasurement
    class CoverageMatrix
      attr_reader :coverage_matrix

      def initialize(array = nil)
        @coverage_matrix = array || Numo::Int32.zeros(0, 0)
      end

      def to_oneshot_lines
        @coverage_matrix[@coverage_matrix.ne(0).where] = 1
      end

      def new_row(spec_index, covered_codes_files_count)
        @coverage_matrix = if @coverage_matrix.empty?
          Numo::Int32.zeros(1, covered_codes_files_count)
        else
          @coverage_matrix.insert([spec_index], Numo::Int16.zeros(1, covered_codes_files_count), axis: 0)
        end
      end

      def new_column(file_index, spec_index)
        @coverage_matrix = @coverage_matrix.insert([file_index], Numo::Int16.zeros(spec_index, 1), axis: 1)
      end

      def times_covered_by_spec(file_indices)
        @coverage_matrix[0..-1, file_indices].sum(axis: 1)

      rescue Numo::NArray::ShapeError
        nil
      end

      def slice_by_files(file_indices, options = { by_specs: false })
        file_indices = (0..-1) if file_indices.none?
        non_zero_spec_indices = @coverage_matrix[0..-1, file_indices].ne(0).any?(1)
        spec_slice = options[:by_specs] ? non_zero_spec_indices : (0..-1)
        @coverage_matrix[spec_slice, file_indices]
      end

      def +(spec_index, file_index, times_covered)
        @coverage_matrix[spec_index, file_index] += times_covered
      end

      def [](spec_index, file_index)
        @coverage_matrix[spec_index, file_index]
      end

      def []=(spec_index, file_index, times_covered)
        @coverage_matrix[spec_index, file_index] = times_covered
      end

      def shape
        @coverage_matrix.shape
      end

      def to_binary
        @coverage_matrix.to_binary
      end

      def to_file
        File.open(Paths::COVERAGE_MATRIX_FILE, 'w') do |f|
          f.puts Numo::Int32.linspace(-1, @coverage_matrix.shape[1], coverage_matrix.shape[1]).format_to_a.join(',')
          (0..@coverage_matrix.shape[0] - 1).each do |index|
            f.puts @coverage_matrix[index, true].format_to_a.join(',').prepend("#{index},")
          end
        end
      end
    end
  end
end
