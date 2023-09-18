module Testsort
  class Prioritization
    module Strategies
      class Additional < AdditionalPseudo
        def prioritized_spec_order(in_groups: false)
          return spec_file_to_index.file_list if affected_file_indices.none?

          ordered_indices = []
          ordered_indices_2 = []
          prioritized_matrix_with_bins_column_sorted[0..-2, true].each_over_axis(0) do |row|
            ordered_indices.append(*row[row.ne(0).where].to_a)
            ordered_indices_2.append(*row[row.ne(0).where].to_a)
          end

          additional_order = []
          ordered_indices.each.with_index do |spec_index_1, spec_list_index_1|
            next if ordered_indices[spec_list_index_1] == -1

            covered_affected_files_1 = @coverage_matrix_narray[spec_index_1, true].ne(0).where.to_a
            additional_order << spec_index_1
            ordered_indices[spec_list_index_1] = -1
            ordered_indices[spec_list_index_1 + 1..].each.with_index do |spec_index_2, spec_list_index_2|
              current_index = spec_list_index_2 + spec_list_index_1 + 1
              next if spec_index_2 == -1 || ordered_indices[current_index] == -1

              covered_affected_files_2 = @coverage_matrix_narray[spec_index_2, true].ne(0).where.to_a
              not_covered_indices = covered_affected_files_2 - covered_affected_files_1
              next if not_covered_indices.empty?

              additional_order << spec_index_2
              ordered_indices[current_index] = -1
              covered_affected_files_1.append(*not_covered_indices)
            end

            # for each index after
            # set the chosen index to nil
            # choose all non nil indices that remain
            # always add new elements to the chovered_list
            # after all elements have been picked reset the covered list to empty and iterate again
          end

          additional_order.append(*prioritized_matrix_with_bins_column_sorted[-1, true].to_a)
          spec_file_to_index.fetch_specs(additional_order.map(&:to_s))
        end
      end
    end
  end
end
