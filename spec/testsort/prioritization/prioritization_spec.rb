# frozen_string_literal: true

describe Testsort::Prioritization do
  # Build a lightweight prioritization using the Absolute strategy for integration,
  # plus direct tests of the base class composition logic.

  let(:coverage_matrix) do
    Testsort::CoverageMeasurement::CoverageMatrix.new(
      Numo::Int32[[10, 0], [8, 0], [0, 5], [0, 0]]
    )
  end

  let(:code_file_to_index) do
    Testsort::CoverageMeasurement::FileToIndexMapping.new(
      path_hash: { 'app/models/user.rb' => 0, 'app/models/post.rb' => 1 },
      index_hash: { 0 => 'app/models/user.rb', 1 => 'app/models/post.rb' }
    )
  end

  let(:spec_file_to_index) do
    Testsort::CoverageMeasurement::FileToIndexMapping.new(
      path_hash: {
        'spec/models/user_spec.rb:1' => 0,
        'spec/models/user_spec.rb:2' => 1,
        'spec/models/post_spec.rb:1' => 2,
        'spec/other_spec.rb:1' => 3,
      },
      index_hash: {
        '0' => 'spec/models/user_spec.rb:1',
        '1' => 'spec/models/user_spec.rb:2',
        '2' => 'spec/models/post_spec.rb:1',
        '3' => 'spec/other_spec.rb:1',
      }
    )
  end

  let(:measurement) do
    double('CoverageMeasurement',
           coverage_matrix: coverage_matrix,
           code_file_to_index: code_file_to_index,
           spec_file_to_index: spec_file_to_index)
  end

  before do
    # Record line vectors for matrix
    coverage_matrix.record(0, 0, hit_count: 10, lines: [5, 6, 7, 8, 9, 10])
    coverage_matrix.record(1, 0, hit_count: 8, lines: [15, 16, 17, 18, 19, 20])
    coverage_matrix.record(2, 1, hit_count: 5, lines: [1, 2, 3, 4, 5])
  end

  describe '#prioritized_spec_order (tier composition)' do
    context 'when line_level is false' do
      around do |example|
        original = Testsort.configuration.line_level
        Testsort.configuration.line_level = false
        example.run
      ensure
        Testsort.configuration.line_level = original
      end

      it 'delegates to rank_all and ignores tier composition' do
        changeset = instance_double(Testsort::Changeset, affected: ['app/models/user.rb'])
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)

        expect(strategy).to receive(:rank_all).with(in_groups: false).and_call_original
        result = strategy.prioritized_spec_order(in_groups: false)
        expect(result).to be_an(Array)
      end
    end

    context 'when line_level is true' do
      around do |example|
        original = Testsort.configuration.line_level
        Testsort.configuration.line_level = true
        example.run
      ensure
        Testsort.configuration.line_level = original
      end

      it 'composes changed_spec_files + line_matched + rank_remaining' do
        changeset = instance_double(Testsort::Changeset)
        allow(changeset).to receive(:affected).and_return([
          'app/models/user.rb',
          'spec/models/post_spec.rb',
        ])
        allow(changeset).to receive(:old_paths_by_new_path).and_return({})
        allow(changeset).to receive(:hunks_for).and_return([])
        allow(changeset).to receive(:diff_hunks).and_return({})
        allow(changeset).to receive(:spec_diff_hunks).and_return({})

        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)
        result = strategy.prioritized_spec_order(in_groups: false)

        # Tier 1: changed spec files (post_spec.rb)
        expect(result.first).to eq('spec/models/post_spec.rb')
        # Tier 2: line-matched examples covering user.rb (since hunks empty, file-level fallback)
        # both user_spec.rb:1 and user_spec.rb:2 match
        expect(result[1..2]).to contain_exactly('spec/models/user_spec.rb:1', 'spec/models/user_spec.rb:2')
        # Tier 3: remaining (post_spec.rb:1 and other_spec.rb:1, not in prior tiers)
        remaining = result[3..]
        expect(remaining).to include('spec/other_spec.rb:1')
      end

      it 'excludes specs in earlier tiers from the remaining tier' do
        changeset = instance_double(Testsort::Changeset)
        allow(changeset).to receive(:affected).and_return(['app/models/user.rb'])
        allow(changeset).to receive(:old_paths_by_new_path).and_return({})
        allow(changeset).to receive(:hunks_for).and_return([])
        allow(changeset).to receive(:diff_hunks).and_return({})
        allow(changeset).to receive(:spec_diff_hunks).and_return({})

        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)
        result = strategy.prioritized_spec_order(in_groups: false)

        # No duplicates: each spec appears at most once
        expect(result.uniq.length).to eq(result.length)
      end
    end
  end

  describe '#affected_example_indices' do
    around do |example|
      original = Testsort.configuration.line_level
      Testsort.configuration.line_level = true
      example.run
    ensure
      Testsort.configuration.line_level = original
    end

    it 'falls back to file-level when hunks are empty' do
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(['app/models/user.rb'])
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).with('app/models/user.rb').and_return([])
      allow(changeset).to receive(:diff_hunks).and_return({})

      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)
      # Both examples covering user.rb should be returned
      expect(strategy.affected_example_indices).to contain_exactly(0, 1)
    end

    it 'resolves renamed files via old_paths_by_new_path' do
      # Coverage indexed under OLD path; changeset reports NEW path as affected.
      renamed_code_index = Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/models/old_user.rb' => 0 },
        index_hash: { 0 => 'app/models/old_user.rb' }
      )
      measurement_with_rename = double('CoverageMeasurement',
                                       coverage_matrix: coverage_matrix,
                                       code_file_to_index: renamed_code_index,
                                       spec_file_to_index: spec_file_to_index)

      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(['app/models/new_user.rb'])
      allow(changeset).to receive(:old_paths_by_new_path).and_return(
        'app/models/new_user.rb' => 'app/models/old_user.rb'
      )
      allow(changeset).to receive(:hunks_for).with('app/models/new_user.rb').and_return([])
      allow(changeset).to receive(:diff_hunks).and_return({})

      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement_with_rename)
      # Should still find specs covering the old path's coverage
      expect(strategy.affected_example_indices).to contain_exactly(0, 1)
    end

    it 'handles nil lines_for without crashing (falls through)' do
      # Example 3 has coverage_matrix[3, 0] == 0, so never reached. Force a case:
      # make coverage > 0 but no line vector recorded.
      # spec index 3 (other_spec) × file 0: currently 0. Use a fresh fixture.
      matrix = Testsort::CoverageMeasurement::CoverageMatrix.new(
        Numo::Int32[[1]]
      )
      # Do NOT record lines — lines_for returns nil
      code_idx = Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/a.rb' => 0 },
        index_hash: { 0 => 'app/a.rb' }
      )
      spec_idx = Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'spec/a_spec.rb:1' => 0 },
        index_hash: { '0' => 'spec/a_spec.rb:1' }
      )
      m = double('CM', coverage_matrix: matrix, code_file_to_index: code_idx, spec_file_to_index: spec_idx)

      # A hunk with a deletion so we take the line-level branch
      hunk = double('Hunk', old_start: 1, old_lines: 1, new_lines: 1)
      deletion_line = double('Line', old_lineno: 1, line_origin: :deletion)
      allow(hunk).to receive(:each_line) do |&block|
        if block
          block.call(deletion_line)
        else
          [deletion_line].each
        end
      end
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(['app/a.rb'])
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).with('app/a.rb').and_return([hunk])
      allow(changeset).to receive(:diff_hunks).and_return({ 'app/a.rb' => [hunk] })

      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, m)
      expect { strategy.affected_example_indices }.not_to raise_error
      # No match since lines_for is nil
      expect(strategy.affected_example_indices).to eq([])
    end

    it 'skips early when changed_old_lines is empty (pure-context after deletions)' do
      # Hunk has no :deletion lines; pure_insertion? is true so we hit file-fallback anyway.
      # Force a hunk with neither deletions nor being pure_insertion? false:
      # The code path: hunks non-empty, pure_insertion? false → changed_lines may be empty
      # Actually, pure_insertion? is true iff no :deletion lines. So "hunks non-empty + not pure-insertion + changed_lines empty" is impossible for real diffs.
      # We verify the early-next path by constructing hunks where pure_insertion is false (has deletion)
      # but the deletion is filtered — use a fake with a :context only line BUT we claim pure_insertion false.
      # Easier: stub DiffOffsetAdjuster.pure_insertion? to false and changed_old_lines to [].
      hunk = double('Hunk')
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(['app/models/user.rb'])
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).with('app/models/user.rb').and_return([hunk])
      allow(changeset).to receive(:diff_hunks).and_return({ 'app/models/user.rb' => [hunk] })

      allow(Testsort::DiffOffsetAdjuster).to receive(:pure_insertion?).and_return(false)
      allow(Testsort::DiffOffsetAdjuster).to receive(:changed_old_lines).and_return([])

      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)
      # Should early-next, no matches
      expect(strategy.affected_example_indices).to eq([])
    end
  end
end
