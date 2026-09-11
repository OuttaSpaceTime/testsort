module Testsort
  class CoverageMeasurement
    module Storage
      module Serializer
        include IOHelper

        SCHEMA_VERSION = 1
        REPREPARE_MESSAGE = 'Coverage store is incompatible with the current configuration or gem version. Please re-run `testsort prepare`.'.freeze

        def serialize
          FileUtils.mkdir('testsort') unless Dir.exist?(Testsort::Paths::GEM_STORAGE)

          IOHelper.exclusively_locked_dir_access(Paths::GEM_STORAGE) do
            write_binary_coverage_matrix
            write_coverage_matrix_shape

            IOHelper.write_json(Paths::SPEC_TO_INDEX, @spec_file_to_index.path_hash)
            IOHelper.write_json(Paths::FILE_TO_INDEX, @code_file_to_index.path_hash)

            IOHelper.write_json(Paths::INDEX_TO_SPEC, @spec_file_to_index.index_hash)
            IOHelper.write_json(Paths::INDEX_TO_FILE, @code_file_to_index.index_hash)

            if Testsort.configuration.line_level
              IOHelper.write_json(Paths::LINE_VECTORS, @coverage_matrix.lines_as_json_data)
            end

            write_meta_atomically
          end
        end

        def deserialize(options = {})
          IOHelper.exclusively_locked_dir_access(Paths::GEM_STORAGE) do
            verify_meta_compatibility!

            @spec_file_to_index = FileToIndexMapping.new(path_hash: IOHelper.read_json(Paths::SPEC_TO_INDEX),
                                                         index_hash: IOHelper.read_json(Paths::INDEX_TO_SPEC))
            @code_file_to_index = FileToIndexMapping.new(path_hash: IOHelper.read_json(Paths::FILE_TO_INDEX),
                                                         index_hash: IOHelper.read_json(Paths::INDEX_TO_FILE))
            @coverage_matrix = CoverageMatrix.new(Numo::Int32.from_binary(read_binary_coverage_matrix, read_coverage_matrix_shape))

            if Testsort.configuration.line_level && File.exist?(Paths::LINE_VECTORS)
              @coverage_matrix.load_lines_from_json_data(IOHelper.read_json(Paths::LINE_VECTORS))
            end
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

        def write_meta_atomically
          meta = {
            'schema_version' => SCHEMA_VERSION,
            'line_level' => !!Testsort.configuration.line_level,
            'measured_at_sha' => current_head_sha,
          }
          final_path = Paths::META
          tmp_path = "#{final_path}.tmp"
          IOHelper.write_json(tmp_path, meta)
          File.rename(tmp_path, final_path)
        end

        def current_head_sha
          Rugged::Repository.new(Paths.root).head.target_id
        rescue Rugged::Error, Rugged::ReferenceError
          nil
        end

        def verify_meta_compatibility!
          unless File.exist?(Paths::META)
            raise Testsort::Error::CoverageStoreIncompatible, REPREPARE_MESSAGE
          end

          meta = IOHelper.read_json(Paths::META) || {}

          if meta['schema_version'] != SCHEMA_VERSION
            raise Testsort::Error::CoverageStoreIncompatible, REPREPARE_MESSAGE
          end

          # Allow loading a line_level=true baseline with line_level=false config
          # (line vectors are extra data that file-level prioritization ignores).
          # The reverse (line_level=false on disk, true config) is incompatible
          # because line vectors aren't there to load.
          if !!Testsort.configuration.line_level && !meta['line_level']
            raise Testsort::Error::CoverageStoreIncompatible, REPREPARE_MESSAGE
          end

          stored_sha = meta['measured_at_sha']
          current_sha = current_head_sha
          if stored_sha && current_sha && stored_sha != current_sha
            $stderr.puts "testsort: coverage store measured_at_sha (#{stored_sha}) differs from current HEAD (#{current_sha}); proceeding anyway."
          end
        end
      end
    end
  end
end
