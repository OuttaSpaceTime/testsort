module Testsort
  module RepositoryManager
    class RepositoryIterator < Repository
      include Memoized

      def initialize
        super
        @commits_without_failures = FileManager.commits_without_failures
        @main_branch = @repo.branches.find { |b| b.name == 'fe/testsort' }
        checkout_base_commit
      end

      def each_pair_with_index
        at_exit do
          checkout_base_commit
        end

        all_commits.each_cons(2).with_index do |commit_tuple, index|
          staged_commit = commit_tuple[0]
          reset_commit = commit_tuple[1]

          stage_commit(staged_commit, reset_commit)
          next if skip_current_commit?(staged_commit, index)

          puts_state(index)
          yield(staged_commit.oid, reset_commit.oid, index)
        end
      end

      def puts_state(index, with_spaces: true)
        super

        puts "Commit #{index + 1}/#{all_commits.count}"
      end

      private

      def skip_current_commit?(staged_commit, index)
        specs_not_changed? ||
          @commits_without_failures.include?(staged_commit.oid) ||
          only_ignored_changes? ||
          index + 1 == all_commits.count - 1 ||
          renamed_files?
      end

      def checkout_base_commit
        @repo.checkout(@main_branch, strategy: :force)
      end

      memoize def all_commits
        all_commits = []
        log_walker.each do |commit|
          all_commits << commit
        end
        all_commits
      end

      def renamed_files?
        @repo.status do |_file, status|
          if status.to_s.include?('index_renamed')
            return true
          end
        end
        false
      end

      def only_ignored_changes?
        ignored_file_types = %w[.js .sass .json .lock Gemfile .haml .yml spec/support routes.rb] | Paths.spec_folder_paths

        @repo.status do |file, status|
          if status.to_s.include?('index') && !include_any?(file, ignored_file_types)
            return false
          end
        end
        true
      end

      def specs_not_changed?
        @repo.status { |file, _status_data| return false if include_any?(file, Paths.spec_folder_paths) }
        true
      end

      def include_any?(should_include, at_least_one_included)
        at_least_one_included.each { |string| return true if should_include.include?(string) }
        false
      end
    end
  end
end
