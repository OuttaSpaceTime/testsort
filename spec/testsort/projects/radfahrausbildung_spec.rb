# frozen_string_literal: true

describe Testsort::Projects::Radfahrausbildung do
  subject(:project) { described_class.new }

  describe '#branch_name' do
    it "returns 'fe/testsort'" do
      expect(project.branch_name).to eq('fe/testsort')
    end
  end

  describe '#spec_folder_paths' do
    it 'returns 9 entries' do
      expect(project.spec_folder_paths.length).to eq(9)
    end

    it 'all entries start with spec/' do
      expect(project.spec_folder_paths).to all(start_with('spec/'))
    end
  end

  describe '#ignored_file_types' do
    it 'includes .js' do
      expect(project.ignored_file_types).to include('.js')
    end

    it 'includes .lock' do
      expect(project.ignored_file_types).to include('.lock')
    end

    it 'includes Gemfile' do
      expect(project.ignored_file_types).to include('Gemfile')
    end
  end

  describe '#setup_commands' do
    context 'when parallel: false (default)' do
      subject(:commands) { project.setup_commands(parallel: false) }

      it 'includes bundle install' do
        expect(commands).to include('bundle install')
      end

      it 'includes yarn install' do
        expect(commands).to include('yarn install')
      end

      it 'ends with the migrate command containing RAILS_ENV=test' do
        expect(commands.last).to include('migrate').and include('RAILS_ENV=test')
      end

      it 'migrate command uses db: prefix' do
        expect(commands.last).to include('db:migrate')
      end
    end

    context 'when parallel: true' do
      subject(:commands) { project.setup_commands(parallel: true) }

      it 'migrate command does NOT contain RAILS_ENV=test' do
        expect(commands.last).not_to include('RAILS_ENV=test')
      end

      it 'migrate command uses parallel: prefix' do
        expect(commands.last).to include('parallel:migrate')
      end
    end
  end

  describe '#change_project_files' do
    around do |example|
      Dir.mktmpdir do |tmpdir|
        FileUtils.mkdir_p(File.join(tmpdir, 'spec'))
        File.write(File.join(tmpdir, 'Gemfile'), "gem 'rails'\n")
        File.write(File.join(tmpdir, 'spec', 'spec_helper.rb'), "RSpec.configure do |config|\nend\n")
        @tmpdir = tmpdir
        example.run
      end
    end

    it 'adds simplecov to the Gemfile' do
      project.change_project_files(@tmpdir)
      expect(File.read(File.join(@tmpdir, 'Gemfile'))).to include('simplecov')
    end

    it 'patches spec_helper.rb to include testsort evaluation require' do
      project.change_project_files(@tmpdir)
      expect(File.read(File.join(@tmpdir, 'spec', 'spec_helper.rb'))).to include('testsort/spec_helper_evaluation')
    end

    it 'is idempotent — calling it a second time does not change the Gemfile' do
      project.change_project_files(@tmpdir)
      gemfile_after_first_call = File.read(File.join(@tmpdir, 'Gemfile'))

      project.change_project_files(@tmpdir)
      gemfile_after_second_call = File.read(File.join(@tmpdir, 'Gemfile'))

      expect(gemfile_after_second_call).to eq(gemfile_after_first_call)
    end
  end
end
