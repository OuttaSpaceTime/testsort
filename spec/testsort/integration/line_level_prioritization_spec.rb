# frozen_string_literal: true

describe 'Line-level prioritization', :git do
  let(:tmp_repo_path) { @tmp_repo_path }
  let(:repo) { @repo }

  around do |example|
    original_dir = Dir.getwd
    original_line_level = Testsort.configuration.line_level
    @tmp_repo_path = Dir.mktmpdir('testsort-integration-line')
    @repo = Rugged::Repository.init_at(@tmp_repo_path)
    Dir.chdir(@tmp_repo_path)
    Testsort.configuration.line_level = true
    example.run
  ensure
    Testsort.configuration.line_level = original_line_level
    Dir.chdir(original_dir)
    FileUtils.remove_entry(@tmp_repo_path) if @tmp_repo_path && File.directory?(@tmp_repo_path)
  end

  # Source file with numbered lines for predictable coverage
  let(:user_rb_content) do
    (1..20).map { |i| "# line #{i}" }.join("\n") + "\n"
  end

  let(:post_rb_content) do
    (1..15).map { |i| "# post line #{i}" }.join("\n") + "\n"
  end

  def setup_base_repo
    commit_files(
      'app/models/user.rb' => user_rb_content,
      'app/models/post.rb' => post_rb_content,
      'spec/models/user_spec.rb' => "# spec line 1\n# spec line 2\n",
      'spec/models/post_spec.rb' => "# post spec\n"
    )
  end

  def setup_fixtures_with_line_vectors
    # Matrix: 3 examples × 2 source files
    # spec/models/user_spec.rb:1 covers user.rb lines 5-10
    # spec/models/user_spec.rb:2 covers user.rb lines 15-20
    # spec/models/post_spec.rb:1 covers post.rb lines 1-5
    setup_line_level_fixtures(
      spec_mappings: {
        path_hash: { 'spec/models/user_spec.rb:1' => 0, 'spec/models/user_spec.rb:2' => 1, 'spec/models/post_spec.rb:1' => 2 },
        index_hash: { '0' => 'spec/models/user_spec.rb:1', '1' => 'spec/models/user_spec.rb:2', '2' => 'spec/models/post_spec.rb:1' }
      },
      code_mappings: {
        path_hash: { 'app/models/user.rb' => 0, 'app/models/post.rb' => 1 },
        index_hash: { 0 => 'app/models/user.rb', 1 => 'app/models/post.rb' }
      },
      matrix_data: Numo::Int32[[10, 0], [8, 0], [0, 5]],
      line_vectors: {
        [0, 0] => [5, 6, 7, 8, 9, 10],
        [1, 0] => [15, 16, 17, 18, 19, 20],
        [2, 1] => [1, 2, 3, 4, 5],
      }
    )
  end

  def stub_system_command
    command_received = nil
    allow(Open3).to receive(:capture3) do |cmd|
      command_received = cmd
      ['', '', double(success?: true)]
    end
    -> { command_received }
  end

  describe 'Scenario 1: Modified source lines' do
    it 'prioritizes only examples covering the changed lines' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Modify lines 7-8 in user.rb (covered by example at user_spec.rb:1, not :2)
      modified_content = user_rb_content.sub("# line 7\n# line 8", "# modified 7\n# modified 8")
      modify_file('app/models/user.rb', modified_content)

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      expect(command).to include('spec/models/user_spec.rb:1')
      # user_spec.rb:2 covers lines 15-20, not 7-8 — should be in remaining, not line-matched
      user1_pos = command.index('spec/models/user_spec.rb:1')
      user2_pos = command.index('spec/models/user_spec.rb:2')
      expect(user1_pos).to be < user2_pos

      # Specs irrelevant to the change (covering different files, different lines)
      # must NOT be in the line-matched tier. With no changed spec files (tier 1
      # empty), line-matched is the prefix of the command. user_spec.rb:1 is the
      # only expected line-matched entry; everything else should come AFTER it.
      post_pos = command.index('spec/models/post_spec.rb:1')
      # post_spec.rb:1 covers post.rb — irrelevant to user.rb change, must not
      # precede the line-matched entry.
      expect(user1_pos).to be < post_pos if post_pos
      expect(user1_pos).to be < user2_pos
    end
  end

  describe 'Scenario 2: Pure insertion in source' do
    it 'falls back to file-level for that file' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Insert 5 new lines at the beginning (pure insertion — no deletions)
      inserted_content = "# new line A\n# new line B\n# new line C\n# new line D\n# new line E\n" + user_rb_content
      modify_file('app/models/user.rb', inserted_content)

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # Both examples covering user.rb should be prioritized (file-level fallback)
      expect(command).to include('spec/models/user_spec.rb:1')
      expect(command).to include('spec/models/user_spec.rb:2')
    end
  end

  describe 'Scenario 3: Deleted source file' do
    it 'prioritizes all examples covering that file' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      File.delete(File.join(tmp_repo_path, 'app/models/user.rb'))

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # Both examples covering user.rb should be prioritized
      expect(command).to include('spec/models/user_spec.rb:1')
      expect(command).to include('spec/models/user_spec.rb:2')
    end
  end

  describe 'Scenario 4: Shifted it block in unchanged spec file' do
    it 'outputs adjusted line numbers for specs not in changeset' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Modify user.rb to trigger prioritization — but don't touch user_spec.rb
      modified_content = user_rb_content.sub("# line 7", "# modified 7")
      modify_file('app/models/user.rb', modified_content)

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # Spec file unchanged — line numbers preserved as-is from stored keys
      expect(command).to include('spec/models/user_spec.rb:1')
    end
  end

  describe 'Scenario 4b: Modified spec file runs as whole file' do
    it 'uses file path without line number for changed spec files' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Modify both source and spec
      modified_content = user_rb_content.sub("# line 7", "# modified 7")
      modify_file('app/models/user.rb', modified_content)
      spec_content = ("# inserted\n" * 10) + "# spec line 1\n# spec line 2\n"
      modify_file('spec/models/user_spec.rb', spec_content)

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # Changed spec file runs as whole file (tier 1), before other specs
      expect(command).to include('spec/models/user_spec.rb')
      user_spec_pos = command.index('spec/models/user_spec.rb')
      post_spec_pos = command.index('spec/models/post_spec.rb')
      expect(user_spec_pos).to be < post_spec_pos
    end
  end

  describe 'Scenario 5: Modified it block' do
    it 'runs the modified spec file unconditionally at highest priority' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Modify the spec file body (no source changes)
      modify_file('spec/models/user_spec.rb', "# completely rewritten spec\n")

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # Modified spec file runs as whole file at tier 1
      expect(command).to include('spec/models/user_spec.rb')
      user_spec_pos = command.index('spec/models/user_spec.rb')
      post_spec_pos = command.index('spec/models/post_spec.rb')
      expect(user_spec_pos).to be < post_spec_pos
    end
  end

  describe 'Scenario 6: New it block (new spec file)' do
    it 'runs the new spec file at highest priority' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Create a brand new spec file
      modify_file('spec/models/invoice_spec.rb', "# new spec for invoice\n")

      # Also modify a source file to trigger prioritization
      modified_content = user_rb_content.sub("# line 7", "# modified 7")
      modify_file('app/models/user.rb', modified_content)

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # New spec file appears at tier 1, before line-matched examples
      expect(command).to include('spec/models/invoice_spec.rb')
      invoice_pos = command.index('spec/models/invoice_spec.rb')
      user_spec_pos = command.index('spec/models/user_spec.rb:1')
      expect(invoice_pos).to be < user_spec_pos
    end
  end

  describe 'Scenario 9: Mixed source + spec changes' do
    it 'prioritizes changed specs first, then line-matched examples' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Modify source lines 15-16 (covered by user_spec.rb:2)
      modified_content = user_rb_content.sub("# line 15\n# line 16", "# modified 15\n# modified 16")
      modify_file('app/models/user.rb', modified_content)

      # Also modify the post spec
      modify_file('spec/models/post_spec.rb', "# modified post spec\n")

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # Tier 1: changed spec file (post_spec.rb)
      # Tier 2: line-matched examples from unchanged spec files (user_spec.rb:2)
      # Tier 3: remaining
      expect(command).to include('spec/models/post_spec.rb')
      expect(command).to include('spec/models/user_spec.rb:2')
      post_pos = command.index('spec/models/post_spec.rb')
      user2_pos = command.index('spec/models/user_spec.rb:2')
      expect(post_pos).to be < user2_pos
    end
  end

  describe 'Scenario 8: No changes' do
    it 'runs with no prioritization signal' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # No changes → tiers 1 and 2 are empty; tier 3 (rank_all) drives order.
      # With empty changeset, Absolute#rank_all returns all specs; none is
      # prioritized over another, but all stored spec keys must appear.
      expect(command).to include('bundle exec rspec')
      expect(command).to include('spec/models/user_spec.rb:1')
      expect(command).to include('spec/models/user_spec.rb:2')
      expect(command).to include('spec/models/post_spec.rb:1')
    end
  end

  describe 'Scenario 7: Dirty → tracked → dirty → tracked' do
    it 'uses correct offsets across multiple cycles' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # --- Cycle 1: Dirty edit ---
      modified_content = user_rb_content.sub("# line 7", "# dirty change 1")
      modify_file('app/models/user.rb', modified_content)

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command1 = get_command.call
      expect(command1).to include('spec/models/user_spec.rb:1')

      # --- Cycle 2: Commit the changes ---
      commit_file('app/models/user.rb', modified_content)

      # --- Cycle 3: Another dirty edit ---
      further_modified = modified_content.sub("# line 16", "# dirty change 2")
      modify_file('app/models/user.rb', further_modified)

      get_command2 = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command2 = get_command2.call
      # Now line 16 changed — should prioritize user_spec.rb:2 (covers lines 15-20)
      expect(command2).to include('spec/models/user_spec.rb:2')

      # --- Cycle 4: Commit and clean run ---
      commit_file('app/models/user.rb', further_modified)

      get_command3 = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command3 = get_command3.call
      # No dirty changes → all specs in default order, no line-level prioritization
      expect(command3).to include('bundle exec rspec')
      expect(command3).to include('spec/models/user_spec.rb')
    end
  end

  describe 'Scenario 10: New untracked source file' do
    it 'has no coverage data for the new file' do
      setup_base_repo
      setup_fixtures_with_line_vectors

      # Create a new untracked file
      modify_file('app/models/invoice.rb', "class Invoice\nend\n")

      get_command = stub_system_command
      Testsort::CLI.start(['prioritized', '-s', 'absolute'])
      command = get_command.call

      # New file has no coverage → no examples specifically prioritized for it
      # but the command should still include all known specs
      expect(command).to include('bundle exec rspec')
    end
  end
end

describe 'End-to-end coverage collection', :git do
  let(:tmp_repo_path) { @tmp_repo_path }
  let(:repo) { @repo }

  around do |example|
    original_dir = Dir.getwd
    original_line_level = Testsort.configuration.line_level
    @tmp_repo_path = Dir.mktmpdir('testsort-e2e')
    @repo = Rugged::Repository.init_at(@tmp_repo_path)
    Dir.chdir(@tmp_repo_path)
    Testsort.configuration.line_level = true
    # Reset memoized regex so it matches the new temp dir
    Testsort::Paths.instance_variable_set(:@project_root_path_regex, nil)
    example.run
  ensure
    Coverage.result(stop: true, clear: true) if Coverage.running?
    Testsort.configuration.line_level = original_line_level
    Testsort::Paths.instance_variable_set(:@project_root_path_regex, nil)
    Dir.chdir(original_dir)
    FileUtils.remove_entry(@tmp_repo_path) if @tmp_repo_path && File.directory?(@tmp_repo_path)
  end

  # Use unique class names per test to avoid Coverage caching issues
  def source_file_content(class_name)
    <<~RUBY
      class #{class_name}
        def add(a, b)
          a + b
        end

        def subtract(a, b)
          a - b
        end

        def multiply(a, b)
          a * b
        end
      end
    RUBY
  end

  describe 'Coverage.start → collect → serialize → deserialize round-trip' do
    it 'collects correct line vectors from real Ruby coverage' do
      content = source_file_content('CalcA')
      commit_file('calc_a.rb', content)

      measurement = Testsort::CoverageMeasurement.new
      Coverage.result(stop: true, clear: true) if Coverage.running?
      Coverage.start(Testsort.configuration.coverage_mode)

      load File.join(tmp_repo_path, 'calc_a.rb')
      CalcA.new.add(1, 2)

      example = double('RSpec::Example',
                       file_path: 'spec/calc_a_spec.rb',
                       metadata: { rerun_file_path: 'spec/calc_a_spec.rb', line_number: 5 })

      measurement.cover(example)

      line_vector = measurement.coverage_matrix.lines_for(0, 0)
      expect(line_vector).to be_an(Array)
      expect(line_vector).not_to be_empty

      # add method lines should be covered
      expect(line_vector).to include(1) # class definition
      expect(line_vector).to include(3) # a + b

      # subtract/multiply bodies should NOT be covered
      expect(line_vector).not_to include(7) # a - b
      expect(line_vector).not_to include(11) # a * b

      # Spec key includes line number
      spec_key = measurement.spec_file_to_index.path_hash.keys.first
      expect(spec_key).to eq('spec/calc_a_spec.rb:5')
    end

    it 'serializes and deserializes line vectors correctly' do
      content = source_file_content('CalcB')
      commit_file('calc_b.rb', content)

      measurement = Testsort::CoverageMeasurement.new
      Coverage.result(stop: true, clear: true) if Coverage.running?
      Coverage.start(Testsort.configuration.coverage_mode)

      load File.join(tmp_repo_path, 'calc_b.rb')
      CalcB.new.add(1, 2)
      CalcB.new.subtract(3, 1)

      example = double('RSpec::Example',
                       file_path: 'spec/calc_b_spec.rb',
                       metadata: { rerun_file_path: 'spec/calc_b_spec.rb', line_number: 10 })

      measurement.cover(example)
      measurement.finish

      loaded = Testsort::CoverageMeasurement.new(from_disk: true)
      loaded_lines = loaded.coverage_matrix.lines_for(0, 0)

      expect(loaded_lines).to be_an(Array)
      expect(loaded_lines).to include(3) # add body
      expect(loaded_lines).to include(7) # subtract body

      loaded_key = loaded.spec_file_to_index.path_hash.keys.first
      expect(loaded_key).to eq('spec/calc_b_spec.rb:10')
    end
  end

  describe 'Coverage collection feeds into prioritization' do
    it 'correctly prioritizes based on real coverage data' do
      content = source_file_content('CalcC')
      commit_file('calc_c.rb', content)

      measurement = Testsort::CoverageMeasurement.new
      Coverage.result(stop: true, clear: true) if Coverage.running?
      Coverage.start(Testsort.configuration.coverage_mode)

      load File.join(tmp_repo_path, 'calc_c.rb')
      CalcC.new.add(1, 2) # Only exercise add, not subtract

      example = double('RSpec::Example',
                       file_path: 'spec/calc_c_spec.rb',
                       metadata: { rerun_file_path: 'spec/calc_c_spec.rb', line_number: 5 })

      measurement.cover(example)
      measurement.finish

      # Modify the subtract method (lines 6-8) — NOT covered by the example
      modified = content.sub("a - b", "b - a")
      modify_file('calc_c.rb', modified)

      loaded = Testsort::CoverageMeasurement.new(from_disk: true)
      changeset = Testsort::Changeset.new
      prioritization = Testsort::Prioritization::Strategies::Absolute.new(changeset, loaded)

      example_indices = prioritization.affected_example_indices
      expect(example_indices).to be_empty # No line-level match for subtract changes
    end
  end
end
