module Testsort
  module RepositoryManager
    module FileReset
      class << self
        def prepare_project_files
          @spec_helper_path = File.join(Paths.root, 'spec/spec_helper.rb')
          @gem_file_path = File.join(Paths.root, 'Gemfile')

          delete_files
          add_required_gems
          remove_not_required_gems
          add_lines_to_spec_helper
          remove_lines_from_spec_helper
        end

        private

        def delete_files
          [
            File.join('spec', 'support', 'capybara_screenshot.rb'),
            File.join('.simplecov'),
            File.join('spec', 'rubocop_spec.rb'),
            File.join('spec', 'eslint_spec.rb'),
            Paths::GEM_STORAGE,
          ].each do |file_path|
            FileUtils.rm_rf(file_path)
          end
        end

        def remove_lines_from_spec_helper
          File.open(@spec_helper_path, 'r') do |f|
            File.open("#{@spec_helper_path}.tmp", 'w') do |f_2|
              f.each_line do |line|
                f_2.write(line) unless
                  line.downcase.include?('simplecov') ||
                    line.downcase.include?('screenshot')
              end
            end
          end
          FileUtils.mv "#{@spec_helper_path}.tmp", @spec_helper_path
        end

        def add_lines_to_spec_helper
          File.open(@spec_helper_path, 'a') do |f|
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

              # RSpec.configure do |config|
              #  config.add_formatter 'Fuubar'
              # end

              Capybara.server = :puma, { Silent: true }

              module FormatterOverrides
                # def example_failed(_)
                  # self.failed_count += 1
                  #
                  # progress.clear
                  # increment
                # end

                def example_pending(_); end
                def example_passed(_); end
                def example_failed(_); end
                def dump_failures(_); end
                # def seed(_); end
                # def dump_summary(_); end
              end

              # Fuubar.prepend FormatterOverrides
              RSpec::Core::Formatters::BaseFormatter.prepend FormatterOverrides
              RSpec::Core::Formatters::ProgressFormatter.prepend FormatterOverrides
            RUBY
          end
        end

        def remove_not_required_gems
          File.open(@gem_file_path, 'r') do |f|
            File.open("#{@gem_file_path}.tmp", 'w') do |f_2|
              f.each_line do |line|
                f_2.write(line) unless
                  line_includes_ignored_gem?(line)
              end
            end
          end
          FileUtils.mv "#{@gem_file_path}.tmp", @gem_file_path
        end

        def line_includes_ignored_gem?(line)
          line.downcase.include?('pry') || line.downcase.include?('screenshot') || line.downcase.include?('simplecov')
        end

        def add_required_gems
          File.open(@gem_file_path, 'a') do |f|
            f.puts <<~RUBY
              gem 'testsort', path: '../testsort'
              gem 'fuubar'
              gem 'rspec-retry', group: :test
              gem 'byebug'
            RUBY
          end
        end
      end
    end
  end
end
