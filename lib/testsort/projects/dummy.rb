# frozen_string_literal: true

module Testsort
  module Projects
    # Minimal fixture project used by the parallel_compare integration spec.
    # Points at a temp copy of spec/fixtures/dummy_project built in before(:context).
    # The path is configured at spec time via the class-level accessor.
    class Dummy < Base
      class << self
        attr_accessor :project_root
      end

      def branch_name
        'main'
      end

      def spec_folder_paths
        ['spec/models']
      end

      # No-op: the fixture Gemfile / spec_helper are pre-baked and never
      # need patching (they already require testsort/spec_helper_evaluation).
      def change_project_files(_working_dir)
        # intentionally blank
      end

      # The integration spec stubs ProjectSetup.setup to be a no-op, so
      # this list is never actually executed.  Return a single no-op command
      # so any accidental invocation doesn't explode.
      def setup_commands(parallel: false)
        ['true']
      end
    end
  end
end
