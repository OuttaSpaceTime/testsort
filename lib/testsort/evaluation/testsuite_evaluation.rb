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
        # Pre-seed with previously-captured noise (parent-commit failures)
        # so those exception/location pairs don't count as new faults.
        @exception_tracker = ExceptionTracker.from_file(ENV['noise_baseline_path'])
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

        # Capture noise dump if requested (parent-baseline pass writes here
        # so subsequent passes can load it via noise_baseline_path).
        if ENV['noise_dump_path'].to_s != ''
          dump_path = ENV['noise_dump_path']

          # When running under parallel_rspec each process has a distinct
          # TEST_ENV_NUMBER (empty string for process 1, "2", "3", … for the
          # rest). Process 1 receives an empty TEST_ENV_NUMBER, so we only
          # suffix when the variable is set AND non-empty. Processes 2..N write
          # "<noise_dump_path>.env-N" so their data does not overwrite each
          # other or process 1. The caller is expected to merge these per-env
          # files back into the canonical unsuffixed path after the run via
          # ExceptionTracker.merge_files.
          # Paths.concat_test_env produces "<path>-env-<N>" (hyphen, not dot).
          # The caller's merge step must use the matching glob pattern.
          env_number = ENV['TEST_ENV_NUMBER']
          dump_path = Paths.concat_test_env(dump_path, env_number) if env_number && !env_number.empty?

          @exception_tracker.dump_to(dump_path)
        end
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
