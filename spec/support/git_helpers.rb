# frozen_string_literal: true

RSpec.shared_context 'with temp git repo', :git do
  let(:tmp_repo_path) { @tmp_repo_path }
  let(:repo) { @repo }

  before do
    @tmp_repo_path = Dir.mktmpdir('testsort-test')
    @repo = Rugged::Repository.init_at(@tmp_repo_path)
    allow(Testsort::Paths).to receive(:root).and_return(@tmp_repo_path)
  end

  after do
    FileUtils.remove_entry(@tmp_repo_path) if File.directory?(@tmp_repo_path)
  end

  def commit_file(path, content = 'initial content')
    full_path = File.join(tmp_repo_path, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    repo.index.add(path: path, oid: repo.write(content, :blob), mode: 0100644)
    repo.index.write

    tree = repo.index.write_tree
    author = { name: 'Test', email: 'test@test.com', time: Time.now }
    parents = repo.empty? ? [] : [repo.head.target]
    Rugged::Commit.create(repo, tree: tree, author: author, committer: author,
                          message: "Add #{path}", parents: parents,
                          update_ref: 'HEAD')
  end

  def commit_files(file_hash)
    file_hash.each do |path, content|
      full_path = File.join(tmp_repo_path, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      repo.index.add(path: path, oid: repo.write(content, :blob), mode: 0100644)
    end
    repo.index.write

    tree = repo.index.write_tree
    author = { name: 'Test', email: 'test@test.com', time: Time.now }
    parents = repo.empty? ? [] : [repo.head.target]
    Rugged::Commit.create(repo, tree: tree, author: author, committer: author,
                          message: 'Commit files', parents: parents,
                          update_ref: 'HEAD')
  end

  def modify_file(path, content)
    full_path = File.join(tmp_repo_path, path)
    File.write(full_path, content)
  end

  def setup_line_level_fixtures(spec_mappings:, code_mappings:, matrix_data:, line_vectors: {})
    measurement = Testsort::CoverageMeasurement.new
    measurement.instance_variable_set(:@code_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: code_mappings[:path_hash],
        index_hash: code_mappings[:index_hash]
      ))
    measurement.instance_variable_set(:@spec_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: spec_mappings[:path_hash],
        index_hash: spec_mappings[:index_hash]
      ))
    coverage_matrix = Testsort::CoverageMeasurement::CoverageMatrix.new(matrix_data)
    line_vectors.each do |(example_idx, file_idx), lines|
      coverage_matrix.record(example_idx, file_idx,
                             hit_count: matrix_data[example_idx, file_idx],
                             lines: lines)
    end
    measurement.instance_variable_set(:@coverage_matrix, coverage_matrix)

    measurement.serialize
  end
end
