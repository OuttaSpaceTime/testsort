module Testsort
  module Evaluation
    class ExceptionTracker
      def initialize
        @exception_hash = Hash.new { Set.new }
      end

      def track(exception, exception_causing_line)
        if @exception_hash[exception].include?(exception_causing_line)
          false
        else
          add(exception, exception_causing_line)
          true
        end
      end

      def add(exception, exception_causing_line)
        @exception_hash[exception] = @exception_hash[exception].add(exception_causing_line)
      end
    end
  end
end
