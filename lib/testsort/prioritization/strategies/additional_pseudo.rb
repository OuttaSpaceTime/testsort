module Testsort
  class Prioritization
    module Strategies
      class AdditionalPseudo < Prioritization
        def initialize(changeset, coverage_measurement)
          super(changeset, coverage_measurement)
          @coverage_matrix_narray = coverage_matrix_slice
        end

        def prioritized_spec_order(in_groups: false)
          return spec_file_to_index.file_list if affected_file_indices.none?

          ordered_indices = []
          prioritized_matrix_with_bins_column_sorted.each_over_axis(1) do |column|
            ordered_indices.append(*column[column.ne(0).where].format)
          end

          if in_groups
            spec_groups = []
            group_indices(ordered_indices).each_with_index do |group_array, index|
              spec_groups[index] = spec_file_to_index.fetch_specs(group_array)
            end

            spec_groups
          else
            spec_file_to_index.fetch_specs(ordered_indices)
          end
        end

        private

        def group_indices(indicies)
          num_cpus = Etc.nprocessors - 1
          groups = Array.new(num_cpus)
          num_cpus.times { |idx| groups[idx] = [] }

          indicies.each_with_index do |index, idx|
            current_group = idx % num_cpus
            groups[current_group] << index
          end

          groups
        end

        def prioritized_matrix_with_bins_column_sorted
          prioritized_matrix_with_bins_column_sorted = Numo::Int32.zeros(bincount_for_files_covered_count.shape[0], upper_bound_count)

          bincount_for_files_covered_count.each_with_index do |_, current_bin|
            indices_for_current_bin = count_files_covered.eq(current_bin).where

            if indices_for_current_bin.empty?
              chosen_indices = Numo::Int32.zeros(0)
            else
              maximum_coverage_sorted = absolute_number_files_covered[indices_for_current_bin].sort_index.reverse
              original_indices = mask_absolute_number_files_covered_by_indices_for_current_bin(indices_for_current_bin)
              chosen_indices = original_indices[maximum_coverage_sorted]
            end

            prioritized_matrix_with_bins_column_sorted[- (current_bin + 1), true] = zero_padded_indicies(chosen_indices)
          end

          prioritized_matrix_with_bins_column_sorted
        end

        def zero_padded_indicies(chosen_indices)
          if chosen_indices.blank? || chosen_indices.empty?
            Numo::Int32.zeros(upper_bound_count)
          else
            chosen_indices.append(Numo::Int32.zeros(upper_bound_count - chosen_indices.shape[0]))
          end
        end

        def mask_absolute_number_files_covered_by_indices_for_current_bin(indices_for_current_bin)
          mask = absolute_number_files_covered.new_zeros
          mask[indices_for_current_bin] = 1
          mask.ne(0).where
        end

        def upper_bound_count
          bincount_for_files_covered_count.max + 1
        end

        def bincount_for_files_covered_count
          @bincount_for_files_covered_count ||= count_files_covered.bincount
        end

        def count_files_covered
          @count_files_covered ||= @coverage_matrix_narray.ne(0).count_true(axis: 1)
        end

        def absolute_number_files_covered
          @absolute_number_files_covered ||= @coverage_matrix_narray.sum(axis: 1)
        end
      end
    end
  end
end
