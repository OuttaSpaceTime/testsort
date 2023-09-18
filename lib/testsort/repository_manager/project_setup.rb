module Testsort
  module RepositoryManager
    class ProjectSetup
      def self.setup(parallel: false)
        puts ''

        database_command_prefix = parallel ? 'parallel' : 'db'
        project_setup = new

        Bundler.with_original_env do
          [
            'bundle install',
            'yarn install',
            "rake #{database_command_prefix}:drop",
            "rake #{database_command_prefix}:create",
            "rake #{database_command_prefix}:migrate #{parallel ? '' : 'RAILS_ENV=test'}",
            # 'bin/setup'
          ].each do |command|
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
        end
      end
    end
  end
end
