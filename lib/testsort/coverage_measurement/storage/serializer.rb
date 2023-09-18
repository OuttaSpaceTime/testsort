module Testsort
  class CoverageMeasurement
    module Storage
      module Serializer
        include IOHelper

        def serialize
          FileUtils.mkdir('testsort') unless Dir.exist?(Testsort::Paths::GEM_STORAGE)

          IOHelper.exclusively_locked_dir_access(Paths::GEM_STORAGE) do
            write_binary_coverage_matrix
            write_coverage_matrix_shape

            IOHelper.write_json(Paths::SPEC_TO_INDEX, @spec_file_to_index.path_hash)
            IOHelper.write_json(Paths::FILE_TO_INDEX, @code_file_to_index.path_hash)

            IOHelper.write_json(Paths::INDEX_TO_SPEC, @spec_file_to_index.index_hash)
            IOHelper.write_json(Paths::INDEX_TO_FILE, @code_file_to_index.index_hash)
          end
        end

        def deserialize(options = {})
          IOHelper.exclusively_locked_dir_access(Paths::GEM_STORAGE) do
            @spec_file_to_index = FileToIndexMapping.new(path_hash: IOHelper.read_json(Paths::SPEC_TO_INDEX),
                                                         index_hash: IOHelper.read_json(Paths::INDEX_TO_SPEC))
            @code_file_to_index = FileToIndexMapping.new(path_hash: IOHelper.read_json(Paths::FILE_TO_INDEX),
                                                         index_hash: IOHelper.read_json(Paths::INDEX_TO_FILE))
            @coverage_matrix = CoverageMatrix.new(Numo::Int32.from_binary(read_binary_coverage_matrix, read_coverage_matrix_shape))
          end

          if options[:oneshot_lines]
            @coverage_matrix.to_oneshot_lines
          end
        end

        private

        def write_binary_coverage_matrix
          File.binwrite(Paths::COVERAGE_MATRIX, @coverage_matrix.to_binary)
        end

        def write_coverage_matrix_shape
          shape = @coverage_matrix.shape

          File.open(Paths::SHAPE, 'w') { |f| f.puts "#{shape[0]}\n#{shape[1]}" }
        end

        def read_binary_coverage_matrix
          path = Paths::COVERAGE_MATRIX
          return nil unless File.exist?(path)

          File.binread(path)
        end

        def read_coverage_matrix_shape
          path = Paths::SHAPE
          return nil unless File.exist?(path)

          File.read(path).split.map(&:to_i)
        end
      end
    end
  end
end
