module Testsort
  module RepositoryManager
    class ProjectSetup
      def self.setup(parallel: false)
        puts ''

        project = Testsort.configuration.project
        project.change_project_files(Paths.root)
        project_setup = new

        # with_unbundled_env (not with_original_env) so an outer
        # BUNDLE_GEMFILE override (used to invoke testsort against an
        # external project) does not leak into bundle install / rake.
        Bundler.with_unbundled_env do
          project.setup_commands(parallel: parallel).each do |command|
            project_setup.run(command)
          end

          puts ''
          project_setup
        end
      end

      def run(commands_string)
        _, error_str, status = Open3.capture3(*commands_string.split)
        if status.success?
          puts "#{commands_string} finished"
        else
          puts "#{commands_string} failed"
          puts ''
          puts error_str
          raise Testsort::Error, "Setup command failed: #{commands_string}"
        end
      end
    end
  end
end
