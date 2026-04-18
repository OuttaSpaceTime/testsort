module Testsort
  module RepositoryManager
    class Repository
      def initialize
        @repo = Rugged::Repository.new(Paths.root)
      end

      def stage_commit(staged_commit, reset_commit = nil, verbose: false)
        set_instance_commits(staged_commit, reset_commit)

        checkout(@staged_commit, strategy: :force)
        reset(@reset_commit, strategy: :soft)

        if verbose
          puts_state
        end
      end

      def discard_spec_changes(reset_commit)
        @repo.reset_path(Paths.spec_folder_paths, reset_commit || previous_commit)

        Paths.spec_folder_paths.each do |path|
          Open3.capture3('git', 'restore', path)
        end
        Open3.capture3('git', 'clean', '-f', 'spec')
      end

      def puts_state(_index = nil, with_spaces: false)
        if with_spaces
          4.times { puts '' }
        end

        puts "Checked out commit #{@staged_commit.oid}"
        puts @staged_commit.message.to_s
        puts "Commit was reset to #{previous_commit.oid}"
      end

      def reset_to_baseline(reset_commit)
        @repo.checkout(reset_commit, strategy: :force)
      end

      def lookup(commit_hash)
        @repo.lookup(commit_hash)
      end

      private

      def set_instance_commits(staged_commit, reset_commit)
        @staged_commit = staged_commit.is_a?(String) ? @repo.lookup(staged_commit) : staged_commit

        @reset_commit = if reset_commit.blank?
          previous_commit
        elsif reset_commit.is_a?(String)
          lookup(reset_commit)
        else
          reset_commit
        end
      end

      def previous_commit
        return @reset_commit if @reset_commit.present?

        log_enumerator = log_walker.walk
        log_enumerator.next
        log_enumerator.next
      end

      def log_walker
        walker = Rugged::Walker.new(@repo)
        walker.sorting(Rugged::SORT_DATE)
        walker.push(@staged_commit || @repo.head.target)
        walker
      end

      def checkout(commit, options)
        commit = commit.oid if commit.is_a?(Rugged::Commit)
        @repo.checkout(commit, strategy: options[:strategy])
      end

      def reset(commit, options)
        commit = commit.oid if commit.is_a?(Rugged::Commit)
        @repo.reset(commit, options[:strategy])
      end
    end
  end
end
