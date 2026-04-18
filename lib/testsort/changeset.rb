# frozen_string_literal: true

module Testsort
  class Changeset
    attr_reader :changes

    def initialize
      @repo = Rugged::Repository.new(Paths.root)
      @status = git_status_hash
    end

    def affected
      @status[:modified] | @status[:new_file] | @status[:deleted] | @status[:renamed]
    end

    def old_paths_by_new_path
      @old_paths_by_new_path ||= detect_renames
    end

    def hunks_for(file_path)
      hunks = diff_hunks[file_path]
      return hunks if hunks

      old_path = old_paths_by_new_path[file_path]
      return nil unless old_path

      diff_hunks[old_path]
    end

    def diff_hunks
      @diff_hunks ||= if @repo.empty?
        {}
      else
        diff = @repo.head.target.tree.diff_workdir
        hunks_by_file = {}

        diff.each_patch do |patch|
          file_path = patch.delta.new_file[:path]
          next if file_path.include?(Paths::GEM_STORAGE)

          hunks_by_file[file_path] = patch.each_hunk.to_a
        end

        hunks_by_file
      end
    end

    def spec_diff_hunks
      diff_hunks.select { |path, _| path.start_with?('spec/') }
    end

    private

    def git_status_hash
      status_hash = {
        modified: [],
        deleted: [],
        new_file: [],
        renamed: [],
      }

      renames = old_paths_by_new_path
      renamed_new_paths = renames.keys.to_set
      renamed_old_paths = renames.values.to_set
      already_renamed = Set.new

      @repo.status do |file, status_data|
        next if file.include?(Paths::GEM_STORAGE)

        if renamed?(status_data) || renamed_new_paths.include?(file)
          status_hash[:renamed] << file if already_renamed.add?(file)
          next
        end

        next if renamed_old_paths.include?(file) || renamed_new_paths.include?(file)

        status_hash[:modified] << file if modified?(status_data)
        status_hash[:deleted] << file if deleted?(status_data)
        status_hash[:new_file] << file if new_file?(status_data)
      end

      status_hash
    end

    def detect_renames
      return {} if @repo.empty?

      head_tree = @repo.head.target.tree
      diff = head_tree.diff(@repo.index)
      diff.find_similar!(renames: true)

      mapping = {}
      diff.each_delta do |delta|
        next unless delta.status == :renamed

        old_path = delta.old_file[:path]
        new_path = delta.new_file[:path]
        next if old_path == new_path
        next if (delta.old_file[:mode] || 0).zero?
        next if new_path.include?(Paths::GEM_STORAGE) || old_path.include?(Paths::GEM_STORAGE)

        mapping[new_path] = old_path
      end
      mapping
    rescue Rugged::ReferenceError, Rugged::Error
      {}
    end

    def renamed?(status_data)
      include_any?(%i[index_renamed worktree_renamed], status_data)
    end

    def modified?(status_data)
      include_any?(%i[index_modified worktree_modified], status_data)
    end

    def deleted?(status_data)
      include_any?(%i[index_deleted worktree_deleted], status_data)
    end

    def new_file?(status_data)
      include_any?(%i[index_new worktree_new], status_data)
    end

    def include_any?(required_status, status_data)
      required_status.any? { |required| status_data.include?(required) }
    end
  end
end
