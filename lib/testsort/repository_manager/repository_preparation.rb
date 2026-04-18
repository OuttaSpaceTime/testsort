module Testsort
  module RepositoryManager
    module RepositoryPreparation
      class << self
        def prepare(staged_commit, reset_commit, verbose: false, set_state: false, baseline_reset: false, parallel: false)
          @repo = RepositoryManager::Repository.new

          if set_state
            @repo.stage_commit(staged_commit, reset_commit, verbose: verbose)
          end

          if baseline_reset
            @repo.reset_to_baseline(reset_commit)
          end

          prepare_files(staged_commit, reset_commit)
          RepositoryManager::ProjectSetup.setup(parallel: parallel)
        end

        def prepare_files(staged_commit, reset_commit)
          RepositoryManager::FileReset.prepare_project_files
          @repo.discard_spec_changes(reset_commit)
          RepositoryManager::FileManager.use_coverage_data_from_previous_run(staged_commit)
        end
      end
    end
  end
end
