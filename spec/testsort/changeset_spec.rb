# frozen_string_literal: true

describe Testsort::Changeset, :git do
  describe '#affected' do
    it 'detects modified files' do
      commit_file('app/models/user.rb', 'class User; end')
      File.write(File.join(tmp_repo_path, 'app/models/user.rb'), 'class User; modified; end')

      changeset = described_class.new
      expect(changeset.affected).to include('app/models/user.rb')
    end

    it 'detects new untracked files' do
      File.write(File.join(tmp_repo_path, 'new_file.rb'), 'new content')

      changeset = described_class.new
      expect(changeset.affected).to include('new_file.rb')
    end

    it 'detects deleted files' do
      commit_file('app/models/post.rb', 'class Post; end')
      File.delete(File.join(tmp_repo_path, 'app/models/post.rb'))

      changeset = described_class.new
      expect(changeset.affected).to include('app/models/post.rb')
    end

    it 'returns empty array for a clean repo' do
      commit_file('app/models/user.rb', 'class User; end')

      changeset = described_class.new
      expect(changeset.affected).to eq([])
    end

    it 'excludes files in the testsort storage directory' do
      FileUtils.mkdir_p(File.join(tmp_repo_path, 'testsort'))
      File.write(File.join(tmp_repo_path, 'testsort/data.json'), '{}')

      changeset = described_class.new
      expect(changeset.affected).not_to include('testsort/data.json')
    end
  end

  describe '#diff_hunks' do
    it 'returns hunks for modified files' do
      commit_file('app/models/user.rb', "line1\nline2\nline3\n")
      File.write(File.join(tmp_repo_path, 'app/models/user.rb'), "line1\nmodified\nline3\n")

      changeset = described_class.new
      hunks = changeset.diff_hunks

      expect(hunks).to have_key('app/models/user.rb')
      expect(hunks['app/models/user.rb']).not_to be_empty
    end

    it 'returns empty hash for a clean repo' do
      commit_file('app/models/user.rb', 'class User; end')

      changeset = described_class.new
      expect(changeset.diff_hunks).to eq({})
    end

    it 'excludes testsort storage files' do
      commit_file('testsort/data.json', '{}')
      File.write(File.join(tmp_repo_path, 'testsort/data.json'), '{"changed": true}')

      changeset = described_class.new
      expect(changeset.diff_hunks).not_to have_key('testsort/data.json')
    end

    it 'returns empty hash for empty repo' do
      changeset = described_class.new
      expect(changeset.diff_hunks).to eq({})
    end
  end

  describe 'renames' do
    # Rugged detects renames by comparing HEAD tree to worktree; a rename shows
    # as a delete of the old path + a new file at the new path with identical
    # content. The index status reports it as index_renamed (when staged) or
    # the pair of deleted/new (for worktree). We verify both the affected list
    # and the new -> old path mapping.
    def setup_rename(old_path, new_path, content)
      commit_file(old_path, content)

      # Stage rename via index so rugged reports it as index_renamed
      full_old = File.join(tmp_repo_path, old_path)
      full_new = File.join(tmp_repo_path, new_path)
      FileUtils.mkdir_p(File.dirname(full_new))
      FileUtils.mv(full_old, full_new)

      repo.index.remove(old_path)
      repo.index.add(path: new_path, oid: repo.write(content, :blob), mode: 0100644)
      repo.index.write
    end

    it 'includes the renamed new path in #affected' do
      setup_rename('app/models/old_name.rb', 'app/models/new_name.rb', "class Foo; end\n")

      changeset = described_class.new
      expect(changeset.affected).to include('app/models/new_name.rb')
    end

    it 'exposes the rename mapping via #old_paths_by_new_path' do
      setup_rename('app/models/old_name.rb', 'app/models/new_name.rb', "class Foo; end\n")

      changeset = described_class.new
      expect(changeset.old_paths_by_new_path).to eq(
        'app/models/new_name.rb' => 'app/models/old_name.rb'
      )
    end

    it 'returns an empty rename map when there are no renames' do
      commit_file('app/models/user.rb', 'class User; end')
      modify_file('app/models/user.rb', 'class User; modified; end')

      changeset = described_class.new
      expect(changeset.old_paths_by_new_path).to eq({})
    end

    it '#hunks_for falls back to the old path when the file was renamed' do
      old_content = "line1\nline2\nline3\n"
      new_content = "line1\nmodified\nline3\n"

      commit_file('app/models/old_name.rb', old_content)
      full_old = File.join(tmp_repo_path, 'app/models/old_name.rb')
      full_new = File.join(tmp_repo_path, 'app/models/new_name.rb')
      FileUtils.mv(full_old, full_new)
      File.write(full_new, new_content)

      repo.index.remove('app/models/old_name.rb')
      repo.index.add(path: 'app/models/new_name.rb',
                     oid: repo.write(new_content, :blob), mode: 0100644)
      repo.index.write

      changeset = described_class.new
      # hunks_for should work whether called with new or old path
      expect(changeset.hunks_for('app/models/new_name.rb')).not_to be_nil
    end
  end

  describe '#spec_diff_hunks' do
    it 'returns only spec/ hunks' do
      commit_file('app/models/user.rb', "line1\n")
      commit_file('spec/models/user_spec.rb', "line1\n")
      File.write(File.join(tmp_repo_path, 'app/models/user.rb'), "modified\n")
      File.write(File.join(tmp_repo_path, 'spec/models/user_spec.rb'), "modified\n")

      changeset = described_class.new

      expect(changeset.spec_diff_hunks.keys).to include('spec/models/user_spec.rb')
      expect(changeset.spec_diff_hunks.keys).not_to include('app/models/user.rb')
    end
  end
end
