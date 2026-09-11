# frozen_string_literal: true

module Testsort
  module Projects
    class Radfahrausbildung < Base
      # Branch name currently hardcoded in
      # lib/testsort/repository_manager/repository_iterator.rb:9
      def branch_name
        'fe/testsort'
      end

      # Folder list currently hardcoded in lib/testsort/paths.rb ~line 102
      def spec_folder_paths
        %w[features factories controllers jobs models mailers requests views workers].map do |spec_folder|
          File.join('spec', spec_folder)
        end
      end

      # File types that represent "ignored-only" changes in a commit.
      # Currently inlined in repository_iterator.rb:68 inside only_ignored_changes?.
      # Note: this list is a subset of that line — the Paths.spec_folder_paths entries
      # are intentionally excluded here because spec_folder_paths is its own method.
      def ignored_file_types
        %w[.js .sass .json .lock Gemfile .haml .yml spec/support routes.rb]
      end

      # Command sequence ported from
      # lib/testsort/repository_manager/project_setup.rb.
      # Returns an Array of shell command strings to set up the project.
      def setup_commands(parallel: false)
        database_command_prefix = parallel ? 'parallel' : 'db'
        [
          'bundle install',
          'yarn install',
          "rake #{database_command_prefix}:drop",
          "rake #{database_command_prefix}:create",
          "rake #{database_command_prefix}:migrate#{parallel ? '' : ' RAILS_ENV=test'}",
        ]
      end

      # Preserves backward compatibility with the legacy FileReset pipeline:
      # this subclass historically depended on FileReset.prepare_project_files
      # running ahead of ProjectSetup.setup. Other project hooks default to
      # false (their change_project_files method does the full job).
      def legacy_file_reset?
        true
      end

      # Patches the project's Gemfile and spec/spec_helper.rb so that testsort
      # coverage measurement works.
      #
      # Idempotency: if the Gemfile already contains 'simplecov' the method
      # returns early without changes.
      # TODO (forge ledger L11): decide whether presence of 'simplecov' is the
      # right idempotency signal, or whether a dedicated marker should be used.
      def change_project_files(working_dir)
        gem_file_path = File.join(working_dir, 'Gemfile')
        spec_helper_path = File.join(working_dir, 'spec', 'spec_helper.rb')

        # Idempotency guard
        return if File.read(gem_file_path).include?('simplecov')

        remove_unwanted_gem_lines(gem_file_path)
        add_required_gems(gem_file_path)
        remove_unwanted_spec_helper_lines(spec_helper_path)
        add_lines_to_spec_helper(spec_helper_path)
      end

      private

      def remove_unwanted_gem_lines(gem_file_path)
        rewrite_file(gem_file_path) do |line|
          !line_includes_ignored_gem?(line)
        end
      end

      def line_includes_ignored_gem?(line)
        line.downcase.include?('pry') ||
          line.downcase.include?('screenshot') ||
          line.downcase.include?('simplecov')
      end

      def add_required_gems(gem_file_path)
        File.open(gem_file_path, 'a') do |f|
          f.puts <<~RUBY
            gem 'testsort', path: '../testsort'
            gem 'simplecov', require: false, group: :test
            gem 'fuubar'
            gem 'rspec-retry', group: :test
            gem 'byebug'
          RUBY
        end
      end

      def remove_unwanted_spec_helper_lines(spec_helper_path)
        rewrite_file(spec_helper_path) do |line|
          !(line.downcase.include?('simplecov') || line.downcase.include?('screenshot'))
        end
      end

      def add_lines_to_spec_helper(spec_helper_path)
        File.open(spec_helper_path, 'a') do |f|
          f.puts <<~RUBY
            require 'testsort/spec_helper_evaluation'
            require 'fuubar'
            require 'rspec/retry'

            RSpec.configure do |config|
              config.around :each, :js do |ex|
                ex.run_with_retry retry: 3
              end

              config.retry_callback = proc do |ex|
                if ex.metadata[:js]
                  Capybara.reset!
                end
              end
            end

            Capybara.server = :puma, { Silent: true }

            module FormatterOverrides
              def example_pending(_); end
              def example_passed(_); end
              def example_failed(_); end
              def dump_failures(_); end
            end

            RSpec::Core::Formatters::BaseFormatter.prepend FormatterOverrides
            RSpec::Core::Formatters::ProgressFormatter.prepend FormatterOverrides
          RUBY
        end
      end

      def rewrite_file(path, &keep_line)
        tmp_path = "#{path}.tmp"
        File.open(path, 'r') do |f|
          File.open(tmp_path, 'w') do |f2|
            f.each_line { |line| f2.write(line) if keep_line.call(line) }
          end
        end
        FileUtils.mv(tmp_path, path)
      end
    end
  end
end
