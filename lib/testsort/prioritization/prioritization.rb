module Testsort
  class Prioritization
    delegate :coverage_matrix, :code_file_to_index, :spec_file_to_index, to: :@coverage_measurement

    def initialize(changeset, coverage_measurement)
      @changeset = changeset
      @coverage_measurement = coverage_measurement
      @spec_list = SpecList.new(spec_file_to_index.file_list)
    end

    def prioritized_spec_order(in_groups: false)
      return rank_all(in_groups: in_groups) unless Testsort.configuration.line_level

      changed_spec_files = @changeset.affected.select { |f| f.start_with?('spec/') }
      changed_spec_set = changed_spec_files.to_set
      line_matched = line_matched_spec_keys(changed_spec_set)
      exclude = changed_spec_set | line_matched.to_set

      changed_spec_files + line_matched + rank_remaining(exclude: exclude)
    end

    def rank_all(in_groups: false)
      raise NoMethodError
    end

    def rank_remaining(exclude:)
      rank_all(in_groups: false).reject { |key| exclude.include?(key) }
    end

    def spec_count
      spec_file_to_index&.count || 0
    end

    def affected_file_indices
      files_to_prioritize = @changeset.affected
      files_to_prioritize.map { |file| resolve_code_file_index(file) }.compact
    end

    def coverage_matrix_slice(by_specs: false)
      @coverage_matrix_narray ||= coverage_matrix.slice_by_files(affected_file_indices, by_specs: by_specs)
    end

    def affected_example_indices
      return affected_file_indices unless Testsort.configuration.line_level

      matched_examples = []
      file_fallback_examples = []

      @changeset.affected.each do |file_path|
        file_idx = resolve_code_file_index(file_path)
        next unless file_idx

        hunks = @changeset.hunks_for(file_path) || []

        if hunks.empty? || DiffOffsetAdjuster.pure_insertion?(hunks)
          file_fallback_examples.concat(specs_matching { |spec_idx| coverage_matrix[spec_idx, file_idx] > 0 })
        else
          changed_lines = DiffOffsetAdjuster.changed_old_lines(hunks)
          matched_examples.concat(specs_matching do |spec_idx|
            next false if coverage_matrix[spec_idx, file_idx] == 0
            covered_lines = coverage_matrix.lines_for(spec_idx, file_idx)
            covered_lines && (covered_lines & changed_lines).any?
          end)
        end
      end

      (matched_examples | file_fallback_examples).uniq
    end

    private

    def resolve_code_file_index(file_path)
      idx = code_file_to_index[file_path]
      return idx if idx

      old_path = @changeset.old_paths_by_new_path[file_path]
      old_path ? code_file_to_index[old_path] : nil
    end

    def line_matched_spec_keys(changed_spec_set)
      example_indices = affected_example_indices
      return [] if example_indices.empty?

      keys = spec_file_to_index.fetch_specs(example_indices.map(&:to_s))
      spec_hunks = @changeset.spec_diff_hunks

      keys.filter_map do |key|
        file = spec_key_file(key)
        next if changed_spec_set.include?(file)

        hunks = spec_hunks[file]
        hunks ? (DiffOffsetAdjuster.adjust_spec_key(key, hunks) || key) : key
      end
    end

    def spec_key_file(key)
      file = key.rpartition(':').first
      file.present? ? file : key
    end

    def specs_matching
      spec_file_to_index.path_hash.each_value.select { |spec_idx| yield(spec_idx) }
    end
  end
end
