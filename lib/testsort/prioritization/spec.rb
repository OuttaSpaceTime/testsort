module Testsort
  class Prioritization
    class Spec
      attr_accessor :times_covered, :path

      def initialize(path)
        @path = path
        @times_covered = 0
      end
    end
  end
end
