# frozen_string_literal: true

module Testsort
  module Projects
    class Base
      def branch_name
        raise NotImplementedError, "#{self.class}#branch_name"
      end

      def spec_folder_paths
        raise NotImplementedError, "#{self.class}#spec_folder_paths"
      end

      def setup_commands(parallel: false)
        raise NotImplementedError, "#{self.class}#setup_commands"
      end

      def ignored_file_types
        []
      end

      def change_project_files(working_dir)
        # No-op default; subclasses override to patch Gemfile / spec_helper.
      end

      # Whether RepositoryPreparation should additionally invoke the legacy
      # FileReset.prepare_project_files (hardcoded Radfahrausbildung-style
      # patching). Defaults to false so new project hooks own their patching
      # via change_project_files alone.
      def legacy_file_reset?
        false
      end
    end
  end
end
