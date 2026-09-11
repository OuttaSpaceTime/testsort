# frozen_string_literal: true

module Testsort
  module Evaluation
    # Drives a side-by-side file-level vs line-level APFD comparison against
    # a caller-provided list of commit SHAs.
    #
    # Safety: refuses to run unless preflight checks pass and explicit commit
    # SHAs are passed. Does NOT auto-walk full history.
    class Compare
      # Strategy → env-var overrides for the inner spec subprocess.
      STRATEGY_DEFINITIONS = {
        'file_level' => {
          'line_level' => 'false',
        },
        'line_level' => {
          'line_level'                => 'true',
          'line_level_filter_common'  => 'true',
          'line_level_strength_sort'  => 'true',
        },
        'line_no_common' => {
          'line_level'                => 'true',
          'line_level_filter_common'  => 'false',
          'line_level_strength_sort'  => 'true',
        },
        'line_no_strength' => {
          'line_level'                => 'true',
          'line_level_filter_common'  => 'true',
          'line_level_strength_sort'  => 'false',
        },
        'line_naive' => {
          'line_level'                => 'true',
          'line_level_naive_order'    => 'true',
        },
        'agent' => {
          'line_level'                => 'true',
          'line_level_filter_common'  => 'true',
          'line_level_strength_sort'  => 'true',
        },
        'agent_oneshot' => {
          'line_level'                => 'true',
          'line_level_filter_common'  => 'true',
          'line_level_strength_sort'  => 'true',
        },
      }.freeze

      # Strategies that should be passed to `testsort prioritized -s <name>`
      # rather than the default `-s absolute`. Anything not listed uses absolute
      # so the line-level config variations measured by the existing strategies
      # remain unchanged.
      STRATEGY_PRIORITIZED_ARG = {
        'agent'         => 'agent',
        'agent_oneshot' => 'agent_oneshot',
      }.freeze

      DEFAULT_STRATEGIES = %w[file_level line_level].freeze

      class PreflightError < StandardError; end

      def initialize(io: $stdout)
        @io = io
      end

      def call(parallel: false, files: [], commits: [], project: nil, fresh: false, strategies: nil)
        configure_project(project)
        commits = Array(commits).map(&:strip).reject(&:empty?)
        @strategies = resolve_strategies(strategies)
        preflight!(commits)
        wipe_evaluation_cache if fresh

        # Pin one run_number for the whole compare invocation so all
        # strategies share an evaluation folder.
        @run_number = Paths.run_number

        # Phase 0: per-commit noise capture (run on parent commit). Used
        # to pre-seed ExceptionTracker so pre-existing failures don't
        # count as new faults.
        @io.puts '=== noise (parent commit, capture failure pairs only) ==='
        Testsort.configuration.line_level = true
        commits.each { |sha| capture_noise(sha, parallel: parallel, files: files) }

        # Phase 1: per-commit baseline coverage capture (line_level=true
        # so the data is a superset usable by all strategies).
        @io.puts '=== baseline (line_level=true; capture coverage only) ==='
        Testsort.configuration.line_level = true
        commits.each { |sha| capture_baseline(sha, parallel: parallel, files: files) }

        # Phase 2: per-strategy prioritized passes. We iterate
        # strategy-outermost so the working tree is staged once per
        # commit (heavy bundle/db setup) and reused across strategies.
        commits.each do |sha|
          @io.puts "=== commit #{sha[0, 8]} (per-strategy passes) ==="
          prepare_for_strategy_passes(sha, parallel: parallel)
          @strategies.each do |strategy|
            run_strategy_pass(sha, strategy: strategy, parallel: parallel, files: files)
          end
        end

        report_results
      ensure
        restore_branch
        cleanup_target_artifacts
      end

      private

      def configure_project(name)
        return if name.nil? || name.empty?

        const_name = name.to_s.split(/[_-]/).map(&:capitalize).join
        Testsort.configuration.project = Testsort::Projects.const_get(const_name).new
      end

      def preflight!(commits)
        @io.puts '--- preflight ---'

        if commits.empty?
          raise PreflightError, 'No commits supplied. Pass --commits SHA,SHA,SHA to constrain scope.'
        end

        repo_root = Paths.root
        raise PreflightError, "Not a git repository: #{repo_root}" unless File.directory?(File.join(repo_root, '.git'))

        if File.exist?(File.join(repo_root, 'testsort.gemspec'))
          raise PreflightError, "Refusing to run inside the testsort gem itself (#{repo_root})"
        end

        rails_env = ENV.fetch('RAILS_ENV', '')
        if rails_env == 'production'
          raise PreflightError, "RAILS_ENV=production is not allowed (got #{rails_env.inspect})"
        end

        repo = Rugged::Repository.new(repo_root)
        if repo.workdir != "#{repo_root}/" && repo.workdir != repo_root
          # Sanity, not strict
        end

        dirty_files = []
        repo.status do |file, status_data|
          dirty_files << "#{status_data.inspect} #{file}" unless status_data == [:ignored] || status_data == [:worktree_new]
        end
        unless dirty_files.empty?
          raise PreflightError, "Working tree is dirty in #{repo_root}:\n  #{dirty_files.join("\n  ")}\nCommit or stash first."
        end

        commits.each do |sha|
          begin
            repo.lookup(sha)
          rescue Rugged::OdbError, Rugged::InvalidError, Rugged::Error => e
            raise PreflightError, "Commit not found: #{sha} (#{e.message})"
          end
        end

        project = Testsort.configuration.project
        unless project.is_a?(Testsort::Projects::Base)
          raise PreflightError, "Configuration.project is not a Projects::Base subclass: #{project.inspect}"
        end

        if repo.branches.find { |b| b.name == project.branch_name }.nil?
          raise PreflightError, "Configured branch '#{project.branch_name}' not found in repo at #{repo_root}"
        end

        @io.puts "  repo:     #{repo_root}"
        @io.puts "  branch:   #{project.branch_name}"
        @io.puts "  project:  #{project.class.name}"
        @io.puts "  commits:  #{commits.join(', ')}"
        @io.puts "  RAILS_ENV: #{rails_env.empty? ? '(unset; will default to test)' : rails_env}"
        @io.puts '--- preflight OK ---'
      end

      # Path used to persist the noise-baseline (exception, line) dump.
      def noise_path_for(staged_sha)
        File.join(Paths.coverage_data_path_for(staged_sha), 'noise.json')
      end

      # Run rspec on the PARENT commit (no staged change applied) and dump
      # the resulting ExceptionTracker state to disk. Subsequent passes load
      # this so its failures don't count as new faults.
      def capture_noise(staged_sha, parallel:, files:)
        noise_file = noise_path_for(staged_sha)
        if File.exist?(noise_file)
          @io.puts "  [noise] #{staged_sha[0, 8]} cached, skipping"
          return
        end

        gem_storage = File.join(Paths.root, Paths::GEM_STORAGE)
        FileUtils.rm_rf(gem_storage)

        parent_sha = parent_of(staged_sha)
        @io.puts "  [noise] preparing PARENT #{parent_sha[0, 8]} (parent of #{staged_sha[0, 8]})"

        # Use parent_sha as both staged and reset → checks out parent state
        # with no staged delta, and the FileReset/spec discard logic that
        # follows leaves the spec set at parent too. So this run measures
        # what fails BEFORE the staged commit's changes are introduced.
        RepositoryManager::RepositoryPreparation.prepare(
          parent_sha,
          parent_sha,
          baseline_reset: false,
          set_state: true,
          parallel: parallel,
        )

        subprocess_env = {
          'run_type'           => 'noise',
          'run_number'         => @run_number,
          'oid'                => staged_sha,
          'line_level'         => 'true',
          # Crucial: tell spec_helper_evaluation to DUMP its tracker.
          'noise_dump_path'    => noise_file,
          # And do NOT preload — capture should record everything fresh.
          'noise_baseline_path' => '',
        }
        # parallel_rspec when parallel: true; merge logic in
        # ExceptionTracker.merge_files + Apfd.merge_per_env_files! reassembles
        # per-process data after the run.
        command = parallel ? +'bundle exec parallel_rspec' : +'bundle exec rspec'
        command << ' ' << files.join(' ') if files.any?
        @io.puts "  [noise] running: #{command}"
        Bundler.with_unbundled_env { system(subprocess_env, command) }

        # Merge any per-env noise files produced by parallel processes back
        # into the canonical unsuffixed path. No-op in sequential mode
        # (glob returns empty when no -env-N files exist). Note: the env
        # suffix is hyphen-prefixed (`noise.json-env-2`), not dot-prefixed.
        ExceptionTracker.merge_files(noise_file, *Dir.glob("#{noise_file}-env-*"))

        if File.exist?(noise_file)
          pairs = JSON.parse(File.read(noise_file)).values.map(&:size).sum
          @io.puts "  [noise] captured #{pairs} (exception, line) pairs"
        else
          @io.puts "  [noise] WARN: dump file not produced — proceeding without filter"
        end
      end

      # Run the unprioritized baseline for one commit. Coverage gets written
      # under coverage_data_for(sha) (no run_type) so subsequent prioritized
      # passes can pick it up via FileManager.use_coverage_data_from_previous_run.
      def capture_baseline(staged_sha, parallel:, files:)
        baseline_dir = Paths.coverage_data_for(staged_sha)
        if File.directory?(baseline_dir)
          @io.puts "  [baseline] #{staged_sha[0, 8]} cached, skipping"
          return
        end

        gem_storage = File.join(Paths.root, Paths::GEM_STORAGE)
        FileUtils.rm_rf(gem_storage)

        parent_sha = parent_of(staged_sha)
        @io.puts "  [baseline] preparing #{staged_sha[0, 8]} (parent #{parent_sha[0, 8]})"

        RepositoryManager::RepositoryPreparation.prepare(
          staged_sha,
          parent_sha,
          baseline_reset: false,
          set_state: true,
          parallel: parallel,
        )

        subprocess_env = {
          'run_type'            => 'baseline',
          'run_number'          => @run_number,
          'oid'                 => staged_sha,
          'line_level'          => 'true',
          'noise_baseline_path' => noise_path_for(staged_sha),
        }
        # Plain rspec — no prioritized command, so spec_helper_evaluation
        # captures coverage on a "natural" run.
        # parallel_rspec when parallel: true; merge logic in
        # ExceptionTracker.merge_files + Apfd.merge_per_env_files! reassembles
        # per-process data after the run.
        command = parallel ? +'bundle exec parallel_rspec' : +'bundle exec rspec'
        command << ' ' << files.join(' ') if files.any?
        @io.puts "  [baseline] running: #{command}"
        Bundler.with_unbundled_env { system(subprocess_env, command) }

        # Merge any per-env eval-data files produced by parallel processes
        # into the canonical un-suffixed files. No-op in sequential mode.
        Apfd.merge_per_env_files!(Paths.current_evaluation_data_folder)

        if File.directory?(Testsort::Paths::GEM_STORAGE)
          # Save under the no-suffix path so prioritized passes can read it.
          FileUtils.mkdir_p(Paths.coverage_data_path_for(staged_sha))
          FileUtils.cp_r(Testsort::Paths::GEM_STORAGE, baseline_dir)
        else
          @io.puts "  [baseline] no coverage data captured for #{staged_sha[0, 8]}"
        end
      end

      # Stage the staged commit + bundle/db setup ONCE per commit so that
      # subsequent strategy passes (file_level, line_level, line_no_*) can
      # share the prepared environment. This is the bulk of the per-commit
      # wall-clock cost (~90s of bundle install + db setup), so amortizing
      # it across N strategies is a 5-10x speedup for the full experiment.
      def prepare_for_strategy_passes(staged_sha, parallel:)
        gem_storage = File.join(Paths.root, Paths::GEM_STORAGE)
        FileUtils.rm_rf(gem_storage)

        parent_sha = parent_of(staged_sha)
        @io.puts "  [stage] preparing #{staged_sha[0, 8]} (parent #{parent_sha[0, 8]})"
        RepositoryManager::RepositoryPreparation.prepare(
          staged_sha,
          parent_sha,
          baseline_reset: false,
          set_state: true,
          parallel: parallel,
        )
      end

      # One strategy's prioritized pass for one commit. Reuses the staged
      # working tree from prepare_for_strategy_passes — no bundle/db setup.
      def run_strategy_pass(staged_sha, strategy:, parallel:, files:)
        if File.directory?(Paths.coverage_data_for(staged_sha, strategy))
          @io.puts "  [#{strategy}] #{staged_sha[0, 8]} cached, skipping"
          return
        end

        # Reset testsort/ so a failed strategy doesn't leak stale data.
        gem_storage = File.join(Paths.root, Paths::GEM_STORAGE)
        FileUtils.rm_rf(gem_storage)

        # Restore baseline coverage so the prioritized command has data.
        RepositoryManager::FileManager.use_coverage_data_from_previous_run(staged_sha)

        strategy_env = STRATEGY_DEFINITIONS.fetch(strategy)
        subprocess_env = {
          'run_type'            => strategy,
          'run_number'          => @run_number,
          'oid'                 => staged_sha,
          'noise_baseline_path' => noise_path_for(staged_sha),
        }.merge(strategy_env)

        # agent_oneshot: pull ordering from a per-commit file written
        # externally by a subagent driver before this run.
        if strategy == 'agent_oneshot'
          ordering_path = "/tmp/testsort-agent-ordering-#{staged_sha}.txt"
          unless File.file?(ordering_path)
            @io.puts "  [#{strategy}] missing ordering at #{ordering_path}; skipping"
            return
          end
          subprocess_env['agent_ordering_file'] = ordering_path
        end

        command = build_command(parallel: parallel, files: files, strategy: strategy)
        @io.puts "  [#{strategy}] running: #{command}"
        Bundler.with_unbundled_env { system(subprocess_env, command) }

        # Merge any per-env eval-data files produced by parallel processes
        # into the canonical un-suffixed files. No-op in sequential mode.
        Apfd.merge_per_env_files!(Paths.current_evaluation_data_folder)

        if File.directory?(Testsort::Paths::GEM_STORAGE)
          RepositoryManager::FileManager.save_coverage_data(staged_sha, strategy)
        else
          @io.puts "  [#{strategy}] no coverage data captured for #{staged_sha[0, 8]} — skipping save"
        end
      end

      def resolve_strategies(strategies)
        list = Array(strategies).flat_map { |s| s.to_s.split(',') }.map(&:strip).reject(&:empty?)
        list = DEFAULT_STRATEGIES if list.empty?
        unknown = list - STRATEGY_DEFINITIONS.keys
        if unknown.any?
          raise PreflightError, "Unknown strategy/strategies: #{unknown.join(', ')}. Known: #{STRATEGY_DEFINITIONS.keys.join(', ')}"
        end
        list
      end

      def parent_of(sha)
        repo = Rugged::Repository.new(Paths.root)
        commit = repo.lookup(sha)
        parent = commit.parents.first
        raise PreflightError, "Commit #{sha} has no parent (root commit?)" if parent.nil?
        parent.oid
      end

      def build_command(parallel:, files:, strategy: nil)
        cmd = +'bundle exec testsort prioritized'
        cmd << ' -p true' if parallel
        cmd << " -s #{STRATEGY_PRIORITIZED_ARG.fetch(strategy, 'absolute')}"
        cmd << " #{files.join(' ')}" if files.any?
        cmd
      end

      def report_results
        # Force Paths to see our pinned run_number (override the
        # auto-increment behavior so report aggregates from the same folder
        # the passes wrote to).
        ENV['run_number'] = @run_number
        run_types = @strategies || DEFAULT_STRATEGIES
        results = Apfd.collect_apfd_per_run_type(
          Paths.current_evaluation_data_folder,
          run_types: run_types,
          no_failure_commits: safe_no_failure_commits,
        )

        @io.puts '--- results ---'
        run_types.each do |rt|
          values = results.fetch(rt, [])
          mean = values.empty? ? Float::NAN : Apfd.mean(values)
          @io.puts "  #{rt}: n=#{values.size} mean=#{mean}"
        end

        csv_path = File.join(Paths.current_evaluation_data_folder, 'compare_apfd.csv')
        FileUtils.mkdir_p(File.dirname(csv_path))
        File.write(csv_path, Apfd.to_csv(results))
        @io.puts "Wrote #{csv_path}"

        # Also write a commit-keyed CSV so a per-commit crash can't misalign
        # rows. Reads fault files directly per (commit, strategy) so any
        # missing file shows as blank rather than shifting other columns up.
        write_commit_keyed_csv(run_types)

        results
      end

      def write_commit_keyed_csv(strategies)
        commits_seen = Dir.glob(File.join(Paths.current_evaluation_data_folder, '*-faults-*'))
                          .map { |f| File.basename(f).split('-').first }
                          .uniq
                          .sort

        csv_path = File.join(Paths.current_evaluation_data_folder, 'compare_apfd_by_commit.csv')
        File.open(csv_path, 'w') do |f|
          f.puts(['commit', *strategies].join(','))
          commits_seen.each do |sha|
            row = [sha]
            strategies.each do |strategy|
              fault_file = File.join(Paths.current_evaluation_data_folder, "#{sha}-faults-#{strategy}")
              if File.exist?(fault_file)
                faults = File.read(fault_file).split(',').map(&:to_i)
                next_apfd =
                  if faults.empty? || faults.none? { |v| v != 0 }
                    ''
                  else
                    n_array = Numo::Int32.cast(faults)
                    Apfd.average_percentage_of_fault_detection(n_array, n_array.shape[0]).round(4)
                  end
                row << next_apfd
              else
                row << ''
              end
            end
            f.puts(row.join(','))
          end
        end
        @io.puts "Wrote #{csv_path} (commit-keyed; missing entries leave blanks)"
      end

      # Wipe the evaluation cache (testsort-test-<projectname>) so a fresh
      # run actually re-executes the prioritized command instead of hitting
      # the per-commit coverage_data cache.
      def wipe_evaluation_cache
        cache = Paths.evaluation_storage
        if File.directory?(cache)
          FileUtils.rm_rf(cache)
          @io.puts "  wiped cache: #{cache}"
        end
      end

      # Removes the `testsort/` storage directory the spec run drops into the
      # target repo. Always runs on exit so `git status` stays clean for the
      # next preflight.
      def cleanup_target_artifacts
        repo_root = begin
          Paths.root
        rescue StandardError
          nil
        end
        return unless repo_root

        artifact = File.join(repo_root, Paths::GEM_STORAGE)
        if File.directory?(artifact)
          FileUtils.rm_rf(artifact)
          @io.puts "  removed #{artifact}"
        end
      end

      # Restore working tree to the configured branch so a mid-iteration
      # crash doesn't strand the user with detached HEAD or partial patches.
      def restore_branch
        return unless Testsort.configuration.project.is_a?(Testsort::Projects::Base)

        repo = Rugged::Repository.new(Paths.root)
        branch = repo.branches.find { |b| b.name == Testsort.configuration.project.branch_name }
        return unless branch

        repo.checkout(branch, strategy: :force)
        @io.puts "  restored HEAD to #{branch.name}"
      rescue StandardError => e
        @io.puts "  (could not restore branch: #{e.class}: #{e.message})"
      end

      def safe_no_failure_commits
        RepositoryManager::FileManager.commits_without_failures
      rescue Errno::ENOENT
        []
      end
    end
  end
end
