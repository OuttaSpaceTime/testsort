# frozen_string_literal: true

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

      changed_spec_files = @changeset.affected.select { |f| f.start_with?('spec/') && f.end_with?('_spec.rb') }
      changed_spec_set = changed_spec_files.to_set
      line_matched = line_matched_spec_keys(changed_spec_set)
      exclude = changed_spec_set | line_matched.to_set

      flat = changed_spec_files + line_matched + rank_remaining(exclude: exclude)
      return flat unless in_groups

      round_robin_groups(flat)
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

      # Legacy mode: bypass common-filter and strength-sort entirely, using the
      # original flat-concat-and-uniq implementation.
      if Testsort.configuration.line_level_naive_order
        return affected_example_indices_naive
      end

      # Accumulate strength score per spec across all changed files. The score
      # is the sum of intersection sizes of the spec's covered lines with the
      # changed lines — common-coverage lines (covered by >COMMON_THRESHOLD of
      # specs) are treated as uninformative and skipped, which removes most
      # factory-induced noise.
      matched_strength = Hash.new(0)
      file_fallback_examples = []
      filter_common = Testsort.configuration.line_level_filter_common
      strength_sort = Testsort.configuration.line_level_strength_sort

      @changeset.affected.each do |file_path|
        file_idx = resolve_code_file_index(file_path)
        next unless file_idx

        hunks = @changeset.hunks_for(file_path) || []

        if hunks.empty? || DiffOffsetAdjuster.pure_insertion?(hunks)
          file_fallback_examples.concat(specs_matching { |spec_idx| coverage_matrix[spec_idx, file_idx] > 0 })
        else
          changed_lines = DiffOffsetAdjuster.changed_old_lines(hunks)
          next if changed_lines.empty?

          if filter_common
            informative_lines = filter_common_lines(file_idx, changed_lines)

            # All changed lines are "common" (covered by most specs) — line
            # vectors give us no differentiating signal here, so fall back to
            # file-level matching for this file.
            if informative_lines.empty?
              file_fallback_examples.concat(specs_matching { |spec_idx| coverage_matrix[spec_idx, file_idx] > 0 })
              next
            end
          else
            # Skip common-line filtering — use all changed lines as-is.
            informative_lines = changed_lines
          end

          spec_file_to_index.path_hash.each_value do |spec_idx|
            next if coverage_matrix[spec_idx, file_idx] == 0
            covered_lines = coverage_matrix.lines_for(spec_idx, file_idx)
            next unless covered_lines
            intersection = covered_lines & informative_lines
            matched_strength[spec_idx] += intersection.size if intersection.any?
          end
        end
      end

      if strength_sort
        matched_sorted = matched_strength.sort_by { |_idx, strength| -strength }.map(&:first)
      else
        # Return specs in insertion (first-encountered) order rather than strength order.
        matched_sorted = matched_strength.keys
      end

      matched_set = matched_sorted.to_set
      matched_sorted + file_fallback_examples.reject { |idx| matched_set.include?(idx) }.uniq
    end

    # Threshold: lines covered by more than this fraction of specs are
    # considered "common" (factory-induced, autoload-induced, ApplicationRecord
    # init, etc.) and contribute no signal to line-level prioritization.
    COMMON_LINE_THRESHOLD = 0.5

    # Lazily compute, per file_idx, which lines are "common" — covered by
    # more than COMMON_LINE_THRESHOLD of all specs.
    def common_lines_for(file_idx)
      @common_lines_cache ||= {}
      @common_lines_cache[file_idx] ||= begin
        total_specs = spec_file_to_index.path_hash.size.to_f
        return Set.new if total_specs.zero?

        line_counts = Hash.new(0)
        spec_file_to_index.path_hash.each_value do |spec_idx|
          next if coverage_matrix[spec_idx, file_idx] == 0
          covered_lines = coverage_matrix.lines_for(spec_idx, file_idx)
          covered_lines&.each { |line| line_counts[line] += 1 }
        end

        threshold = total_specs * COMMON_LINE_THRESHOLD
        line_counts.each_with_object(Set.new) do |(line, count), common|
          common << line if count > threshold
        end
      end
    end

    def filter_common_lines(file_idx, changed_lines)
      common = common_lines_for(file_idx)
      changed_lines.reject { |line| common.include?(line) }
    end

    private

    def round_robin_groups(flat_list)
      require 'etc'
      n = (ENV['PARALLEL_TEST_PROCESSORS']&.to_i || Etc.nprocessors).clamp(1, Float::INFINITY)
      groups = Array.new(n) { [] }
      flat_list.each_with_index { |spec, i| groups[i % n] << spec }
      groups
    end

    # Legacy (pre-strength-weighted) implementation: flat concat in spec_index
    # iteration order, no common-line filter, no strength sort.
    def affected_example_indices_naive
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
          next if changed_lines.empty?

          spec_file_to_index.path_hash.each_value do |spec_idx|
            next if coverage_matrix[spec_idx, file_idx] == 0
            covered_lines = coverage_matrix.lines_for(spec_idx, file_idx)
            next unless covered_lines
            matched_examples << spec_idx if (covered_lines & changed_lines).any?
          end
        end
      end

      (matched_examples | file_fallback_examples).uniq
    end

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
