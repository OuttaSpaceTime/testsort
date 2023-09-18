module Testsort
  module Paths
    GEM_STORAGE = 'testsort'.freeze
    SHAPE = "#{GEM_STORAGE}/shape".freeze
    SPEC_TO_INDEX = "#{GEM_STORAGE}/spec_to_index.json".freeze
    FILE_TO_INDEX = "#{GEM_STORAGE}/file_to_index.json".freeze
    INDEX_TO_SPEC = "#{GEM_STORAGE}/index_to_spec.json".freeze
    INDEX_TO_FILE = "#{GEM_STORAGE}/index_to_file.json".freeze
    COVERAGE_MATRIX = "#{GEM_STORAGE}/coverage_matrix.bin".freeze
    COVERAGE_MATRIX_FILE = "#{GEM_STORAGE}/coverage_matrix".freeze

    class << self
      def root
        Dir.getwd
      end

      def relative_path_of(path)
        path.delete_prefix("#{Paths.root}/")
      end

      def evaluation_storage
        File.join(File.expand_path('..', root), "testsort-test-#{root[/([a-zA-Z.\-]*)$/, 1]}")
      end

      def evaluation_data_folder
        File.join(evaluation_storage, 'evaluation')
      end

      def run_number
        set_current_run_number
        @run_number
      end

      def set_current_run_number
        @run_number =
          if ENV['run_number'].present?
            ENV['run_number']
          elsif File.directory? evaluation_data_folder
            (Dir.entries(evaluation_data_folder).map(&:to_i).max + 1).to_s
          else
            '0'
          end
      end

      def evaluation_file_paths(current_test_env_number)
        [
          Paths.evaluation_run_times_path(current_test_env_number),
          Paths.faults_file_path(current_test_env_number),
          Paths.failures_file_path(current_test_env_number),
          Paths.evaluation_executed_spec_paths(current_test_env_number),
        ]
      end

      def current_evaluation_data_folder(use_data_folder: false)
        File.join(evaluation_data_folder, use_data_folder ? 'data' : @run_number)
      end

      def evaluation_file_name(file_content, file_ending = '', run_type: '0', oid: '0')
        "#{ENV.fetch('oid', oid)}-#{file_content}-#{ENV.fetch('run_type', run_type)}#{file_ending}"
      end

      def faults_file_path(test_env_number = nil, run_type: '0', oid: '0', use_data_folder: false)
        path = File.join(current_evaluation_data_folder(use_data_folder: use_data_folder), evaluation_file_name('faults', oid: oid, run_type: run_type))
        path = concat_test_env(path, test_env_number) if test_env_number.present?
        path
      end

      def failures_file_path(test_env_number = nil)
        path = File.join(current_evaluation_data_folder, evaluation_file_name('failures'))
        path = concat_test_env(path, test_env_number) if test_env_number.present?
        path
      end

      def evaluation_plot_path
        File.join(current_evaluation_data_folder, evaluation_file_name('plot', '.jpeg'))
      end

      def evaluation_executed_spec_paths(test_env_number = nil)
        path = File.join(current_evaluation_data_folder, evaluation_file_name('executed_specs'))
        path = concat_test_env(path, test_env_number) if test_env_number.present?
        path
      end

      def evaluation_prioritized_order(test_env_number = nil)
        path = File.join(current_evaluation_data_folder, evaluation_file_name('prioritized_order'))
        path = concat_test_env(path, test_env_number) if test_env_number.present?
        path
      end

      def evaluation_run_times_path(test_env_number = nil)
        path = File.join(current_evaluation_data_folder, evaluation_file_name('execution_times'))
        path = concat_test_env(path, test_env_number) if test_env_number.present?
        path
      end

      def concat_test_env(path, test_env_number)
        "#{path}-env-#{test_env_number}"
      end

      def spec_folder_paths
        %w[features factories controllers jobs models mailers requests views workers].map do |spec_folder|
          File.join('spec', spec_folder)
        end
      end

      def commits_without_failures_path
        File.join(evaluation_storage, 'no_failure_commits')
      end

      def coverage_data
        File.join(evaluation_storage, 'coverage_data')
      end

      def coverage_data_for(commit_hash, strategy_name = '')
        return File.join(Paths.coverage_data_path_for(commit_hash), 'testsort') if ['no_faults', ''].include?(strategy_name)

        File.join(Paths.coverage_data_path_for(commit_hash), "testsort-#{strategy_name}")
      end

      def coverage_data_path_for(commit_hash)
        File.join(coverage_data, commit_hash)
      end

      # check if only one file is present because process might access them overlapping
      def last_run_stored?
        File.exist?(Paths::SHAPE) ||
          File.exist?(Paths::COVERAGE_MATRIX) ||
          File.exist?(Paths::SPEC_TO_INDEX) ||
          File.exist?(Paths::INDEX_TO_SPEC) ||
          File.exist?(Paths::FILE_TO_INDEX) ||
          File.exist?(Paths::INDEX_TO_FILE)
      end

      def project_root_path_regex
        @project_root_path_regex ||= /\A#{Regexp.escape(Paths.root + File::SEPARATOR)}/i
      end
    end
  end
end
