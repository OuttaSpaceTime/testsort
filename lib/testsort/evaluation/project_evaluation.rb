module Testsort
  module Evaluation
    module ProjectEvaluation
      class << self

        include Evaluation::Storage

        def evaluate(files, parallel: false)
          repository_states = RepositoryManager::RepositoryIterator.new
          set_instance_variables(files, parallel)

          repository_states.each_pair_with_index do |staged_commit_hash, reset_commit_hash, index|
            set_variables_for_current_state(staged_commit_hash, reset_commit_hash, index)

            faults_path = Paths.faults_file_path(run_type: 'random', oid: staged_commit_hash, use_data_folder: true)
            if File.exist?(faults_path)
              faults = File.read(faults_path).split(',').map(&:to_i)
              next if faults.all? { |i| i == 0 }
            end

            record_run('no_faults', baseline_reset: true)
            # record_run('random', set_state: true)
            #
            # faults_path = Paths.faults_file_path(run_type: 'random', oid: staged_commit_hash, use_data_folder: false)
            # if File.exist?(faults_path)
            #   faults = File.read(faults_path).split(',').map(&:to_i)
            #   next if faults.all? { |i| i == 0 }
            # end
            #
            # record_run('additional_pseudo', prioritized: true, set_state: true, prepare: false)
            # record_run('additional', prioritized: true, set_state: true, prepare: false)
            record_run('absolute', prioritized: true, set_state: true, prepare: false)
            record_run('oneshot', prioritized: true, set_state: true, prepare: false, to_oneshot_lines: true)
          end
        end

        private

        def record_run(run_type, prioritized: false, baseline_reset: false, set_state: false, prepare: true, to_oneshot_lines: false)
          return if File.directory?(Paths.coverage_data_for(@staged_commit_hash, run_type))

          if prepare || !File.directory?(Paths.coverage_data_for(@staged_commit_hash, run_type))
            RepositoryManager::RepositoryPreparation.prepare(@staged_commit_hash,
                                                             @reset_commit_hash,
                                                             baseline_reset: baseline_reset,
                                                             set_state: set_state,
                                                             parallel: @parallel)
          end

          if prioritized
            RepositoryManager::FileManager.use_coverage_data_from_previous_run(@staged_commit_hash)

            oneshot_lines = ''
            if to_oneshot_lines
              oneshot_lines << ' -o true '
            end

            command = "bundle exec testsort prioritized #{@parallel ? '-p true' : ''} -s #{run_type}"
            command << oneshot_lines
          else
            command = "bundle exec #{@command} #{@command_files_suffix}"
          end

          Bundler.with_original_env do
            set_environment_variables(run_type)
            system(*command)
          end

          RepositoryManager::FileManager.save_coverage_data(@staged_commit_hash, run_type)
        end

        def set_environment_variables(run_type)
          ENV['run_type'] = run_type
          ENV['run_number'] = @current_run_number
          ENV['oid'] = @staged_commit_hash
        end

        def set_instance_variables(files, parallel)
          @current_run_number = Paths.run_number
          @command = parallel ? 'parallel_rspec' : 'rspec'
          @command_files_suffix = files.join(' ')
          @parallel = parallel
        end

        def set_variables_for_current_state(staged_commit_hash, reset_commit_hash, index)
          @staged_commit_hash = staged_commit_hash
          @reset_commit_hash = reset_commit_hash
        end
      end
    end
  end
end
