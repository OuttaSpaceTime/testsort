module Testsort
  class Prioritization
    module Strategies
      class Absolute < Prioritization
        def initialize(changeset, coverage_measurement)
          super(changeset, coverage_measurement)

          @times_covered_by_spec = times_covered_by_spec
          @covered_specs = covered_specs
        end

        def prioritized_spec_order(in_groups: false)
          @spec_list.sorted_by_times_covered
        end

        def select_covered_spec_list
          @spec_list.select_times_covered_sorted
        end

        private

        def covered_specs
          @times_covered_by_spec.each_with_index do |times_covered, spec_index|
            @spec_list[spec_index] = times_covered
          end

          @spec_list
        end

        def times_covered_by_spec
          @times_covered_by_spec ||= coverage_matrix.times_covered_by_spec(affected_file_indices) || []
        end
      end
    end
  end
end
