# frozen_string_literal: true

module Testsort
  class Changeset
    attr_reader :changes

    def initialize
      @repo = Rugged::Repository.new(Paths.root)
      @status = git_status_hash
    end

    def affected
      @status[:modified] | @status[:new_file] | @status[:deleted]
    end

    private

    def git_status_hash
      status_hash = {
        modified: [],
        deleted: [],
        new_file: [],
      }

      @repo.status do |file, status_data|
        next if file.include?(Paths::GEM_STORAGE)

        status_hash[:modified] << file if modified?(status_data)
        status_hash[:deleted] << file if deleted?(status_data)
        status_hash[:new_file] << file if new_file?(status_data)
      end

      status_hash
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
