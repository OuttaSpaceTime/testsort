module Testsort
  module RepositoryManager
    module FileManager
      class << self
        def commits_without_failures
          # return [] unless File.directory?(Paths.commits_without_failures_path)

          File.readlines(Paths.commits_without_failures_path, chomp: true)
        end

        def use_coverage_data_from_previous_run(staged_commit)
          if File.directory?(Paths.coverage_data_for(staged_commit))
            FileUtils.rm_r(Paths::GEM_STORAGE, force: true)
            FileUtils.cp_r(Paths.coverage_data_for(staged_commit), Paths::GEM_STORAGE)
          end
        end

        def clear_data_including(substring)
          return unless File.directory?(Paths.evaluation_storage)

          files_and_directories = Dir.glob(File.join(Paths.evaluation_storage, '**/*/')) | Dir.glob(File.join(Paths.evaluation_storage, '**/*'))
          files_and_directories.each do |path|
            FileUtils.rm_r(path, force: true) if path.include?(substring)
          end
        end

        def save_coverage_data(staged_commit_hash, run_type = '')
          FileUtils.mkdir_p(Paths.coverage_data_path_for(staged_commit_hash))
          FileUtils.cp_r(Paths::GEM_STORAGE, Paths.coverage_data_for(staged_commit_hash, run_type))
        end

        def delete_data_from_previous_run
          [Paths.evaluation_data_folder, Paths.coverage_data].each do |path|
            delete_folder_if_exists(path)
          end
        end

        def delete_folder_if_exists(path)
          if File.directory?(path)
            FileUtils.rm_r(path)
          end
        end
      end
    end
  end
end
