# frozen_string_literal: true

describe Testsort::RepositoryManager::RepositoryIterator do
  describe 'project hook integration' do
    around do |example|
      original_dir = Dir.getwd
      @tmp_repo_path = Dir.mktmpdir('testsort-iter-spec')
      Dir.chdir(@tmp_repo_path)
      example.run
    ensure
      Dir.chdir(original_dir)
      FileUtils.remove_entry(@tmp_repo_path) if @tmp_repo_path && File.directory?(@tmp_repo_path)
    end

    before do
      @repo = Rugged::Repository.init_at(@tmp_repo_path)

      File.write(File.join(@tmp_repo_path, 'README'), 'hi')
      @repo.index.add(path: 'README', oid: @repo.write('hi', :blob), mode: 0100644)
      @repo.index.write
      tree = @repo.index.write_tree
      author = { name: 'T', email: 't@t', time: Time.now }
      Rugged::Commit.create(@repo, tree: tree, author: author, committer: author,
                            message: 'init', parents: [], update_ref: 'HEAD')

      @repo.branches.create('custom-branch', @repo.head.target_id)

      FileUtils.mkdir_p(File.dirname(Testsort::Paths.commits_without_failures_path))
      File.write(Testsort::Paths.commits_without_failures_path, '')
    end

    it 'reads branch_name from the configured project' do
      project = Testsort::Projects::Radfahrausbildung.new
      allow(project).to receive(:branch_name).and_return('custom-branch')
      Testsort.configuration.project = project

      iterator = described_class.new

      expect(iterator.instance_variable_get(:@main_branch).name).to eq('custom-branch')
    end
  end

  describe '#only_ignored_changes? ignored_file_types source' do
    it 'reads ignored_file_types from the configured project' do
      iterator = described_class.allocate
      fake_repo = instance_double(Rugged::Repository)
      iterator.instance_variable_set(:@repo, fake_repo)

      project = instance_double(
        Testsort::Projects::Base,
        ignored_file_types: ['.custom'],
        spec_folder_paths: ['spec/foo'],
      )
      Testsort.configuration.project = project

      allow(fake_repo).to receive(:status) do |&block|
        block.call('lib/app.custom', 'index_modified')
      end
      expect(iterator.send(:only_ignored_changes?)).to eq(true)

      allow(fake_repo).to receive(:status) do |&block|
        block.call('lib/app.rb', 'index_modified')
      end
      expect(iterator.send(:only_ignored_changes?)).to eq(false)
    end
  end
end
