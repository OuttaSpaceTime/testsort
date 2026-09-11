# frozen_string_literal: true

describe 'prioritized command' do
  let(:tmp_repo_path) { @tmp_repo_path }
  let(:repo) { @repo }

  around do |example|
    original_dir = Dir.getwd
    @tmp_repo_path = Dir.mktmpdir('testsort-integration')
    @repo = Rugged::Repository.init_at(@tmp_repo_path)
    Dir.chdir(@tmp_repo_path)
    example.run
  ensure
    Dir.chdir(original_dir)
    FileUtils.remove_entry(@tmp_repo_path) if @tmp_repo_path && File.directory?(@tmp_repo_path)
  end

  def commit_file(path, content = 'initial content')
    full_path = File.join(@tmp_repo_path, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    @repo.index.add(path: path, oid: @repo.write(content, :blob), mode: 0100644)
    @repo.index.write

    tree = @repo.index.write_tree
    author = { name: 'Test', email: 'test@test.com', time: Time.now }
    parents = @repo.empty? ? [] : [@repo.head.target]
    Rugged::Commit.create(@repo, tree: tree, author: author, committer: author,
                          message: "Add #{path}", parents: parents,
                          update_ref: 'HEAD')
  end

  def setup_coverage_fixtures
    measurement = Testsort::CoverageMeasurement.new
    measurement.instance_variable_set(:@code_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/models/user.rb' => 0, 'app/models/post.rb' => 1 },
        index_hash: { 0 => 'app/models/user.rb', 1 => 'app/models/post.rb' }
      ))
    measurement.instance_variable_set(:@spec_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'spec/models/user_spec.rb' => 0, 'spec/models/post_spec.rb' => 1 },
        index_hash: { '0' => 'spec/models/user_spec.rb', '1' => 'spec/models/post_spec.rb' }
      ))
    measurement.instance_variable_set(:@coverage_matrix,
      Testsort::CoverageMeasurement::CoverageMatrix.new(
        Numo::Int32[[5, 0], [0, 3]]
      ))
    measurement.serialize
  end

  def create_modified_file
    commit_file('app/models/user.rb', 'class User; end')
    File.write(File.join(@tmp_repo_path, 'app/models/user.rb'), 'class User; modified; end')
  end

  def stub_system
    command_received = nil
    allow(Open3).to receive(:capture3) do |cmd|
      command_received = cmd
      ['', '', double(success?: true)]
    end
    -> { command_received }
  end

  describe 'with coverage data and changed files' do
    before do
      setup_coverage_fixtures
      create_modified_file
    end

    it 'builds a command with specs ordered by coverage of affected files' do
      get_command = stub_system

      Testsort::CLI.start(['prioritized', '-s', 'absolute'])

      command = get_command.call
      expect(command).to include('bundle exec rspec')
      expect(command).to include('--order defined')
      expect(command).to include('spec/models/user_spec.rb')
      expect(command).to include('spec/models/post_spec.rb')
      user_pos = command.index('spec/models/user_spec.rb')
      post_pos = command.index('spec/models/post_spec.rb')
      expect(user_pos).to be < post_pos
    end
  end

  describe 'without coverage data' do
    it 'falls back to plain rspec command' do
      get_command = stub_system

      Testsort::CLI.start(['prioritized'])

      expect(get_command.call).to eq('bundle exec rspec')
    end
  end

  describe 'with coverage data but no matching changed files' do
    before do
      setup_coverage_fixtures
      commit_file('app/models/comment.rb', 'class Comment; end')
      File.write(File.join(@tmp_repo_path, 'app/models/comment.rb'), 'class Comment; modified; end')
    end

    it 'still builds a command with all specs (sorted by zero coverage)' do
      get_command = stub_system

      Testsort::CLI.start(['prioritized', '-s', 'absolute'])

      command = get_command.call
      expect(command).to include('bundle exec rspec')
      expect(command).to include('spec/models/user_spec.rb')
      expect(command).to include('spec/models/post_spec.rb')
    end
  end
end
