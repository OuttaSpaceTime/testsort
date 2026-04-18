module Testsort
  class Prioritization
    class SpecList
      def initialize(path_list)
        @spec_list = path_list.map { |path| Spec.new(path) }
      end

      def []=(spec_index, times_covered)
        @spec_list[spec_index].times_covered = times_covered
      end

      def count
        @spec_list.count
      end

      def sorted_by_times_covered
        @spec_list&.sort_by { |spec| - spec.times_covered }
          &.map(&:path) || []
      end

      def select_times_covered_sorted
        @spec_list&.select { |spec| spec.times_covered.positive? }
          &.sort_by { |spec| - spec.times_covered }
          &.map(&:path) || []
      end
    end
  end
end
