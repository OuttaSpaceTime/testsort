module Testsort
  module Evaluation
    module Storage
      include IOHelper

      def create_folder_structure
        Paths.set_current_run_number
        FileUtils.mkdir_p(Paths.current_evaluation_data_folder)
      end

      def write_results(gnu_plot = blank)
        write_evaluation_files

        unless gnu_plot.blank?
          gnu_plot.output Paths.evaluation_plot_path
        end
      end

      def write_evaluation_files
        Paths.evaluation_file_paths(current_test_env_number).zip([
          @spec_run_times,
          @failures,
          @faults,
          @executed_specs,
        ]).each do |file_path, data_array|
          File.open(file_path, 'a') do |f|
            f.puts data_array.join(',')
          end
        end
      end

      def current_test_env_number
        return nil if ENV['TEST_ENV_NUMBER'].nil?

        ENV['TEST_ENV_NUMBER'].empty? ? '1' : ENV['TEST_ENV_NUMBER']
      end
    end
  end
end
