require_relative 'storage'

module Testsort
  module Evaluation
    class TestsuiteEvaluation
      delegate :example, to: :@notification
      delegate :execution_result, to: :example

      include Evaluation::Storage

      def initialize
        @faults = []
        @failures = []
        @executed_specs = []
        @executed_spec_files = []
        @spec_run_times = []
        @exception_tracker = ExceptionTracker.new
      end

      def example_finished(notification)
        @notification = notification
        record_example_execution
        record_run_time
        record_execution_result
      end

      def evaluate_suite
        evaluation_metrics = Metrics.new(@faults)
        create_folder_structure
        gnu_plot = evaluation_metrics.plot_results
        write_results(gnu_plot)
      end

      private

      def record_execution_result
        @faults << (count_current_exception? ? 1 : 0)
        @failures << (failed? ? 1 : 0)
      end

      def record_run_time
        @spec_run_times << "#{example.location}-#{execution_result.run_time}"
      end

      def record_example_execution
        @executed_spec_files << example.file_path
        @executed_specs << example.location
      end

      def count_current_exception?
        failed? && @exception_tracker.track(exception, exception_causing_line)
      end

      def failed?
        execution_result.status == :failed
      end

      def exception
        execution_result.exception.to_s
      end

      def exception_causing_line
        @notification.formatted_backtrace[0]
      end
    end
  end
end
