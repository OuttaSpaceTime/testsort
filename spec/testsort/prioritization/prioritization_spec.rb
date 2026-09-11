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

      it 'does not include spec/factories files in changed_spec_files (regression: FactoryBot::DuplicateDefinitionError)' do
        changeset = instance_double(Testsort::Changeset)
        # Simulate commit 94a1a6a9: a factory file and real spec files are both modified
        allow(changeset).to receive(:affected).and_return([
          'app/models/user.rb',
          'spec/factories/note_factory.rb',
          'spec/models/post_spec.rb',
        ])
        allow(changeset).to receive(:old_paths_by_new_path).and_return({})
        allow(changeset).to receive(:hunks_for).and_return([])
        allow(changeset).to receive(:diff_hunks).and_return({})
        allow(changeset).to receive(:spec_diff_hunks).and_return({})

        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)
        result = strategy.prioritized_spec_order(in_groups: false)

        # Factory file must not be passed to rspec — it causes a double-load error
        expect(result).not_to include('spec/factories/note_factory.rb')
        # The real spec file should still be in the output
        expect(result).to include('spec/models/post_spec.rb')
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

  # -------------------------------------------------------------------------
  # Flag: line_level_filter_common
  # -------------------------------------------------------------------------
  # Setup: 4 specs × 1 file. Changed line is 99. Specs 0, 1, 2 all cover
  # line 99 (3 out of 4 > 50% threshold → "common"). Spec 3 does not cover
  # the file at all. With filter_common=true the common line is stripped and
  # no line-level match is produced (only a file-fallback could fire, but
  # nothing reaches that branch since specs 0-2 do match the file). With
  # filter_common=false line 99 stays informative and specs 0-2 are matched.
  describe 'line_level_filter_common flag' do
    let(:filter_common_matrix) do
      # 4 specs × 1 file. Specs 0,1,2 cover the file; spec 3 does not.
      m = Testsort::CoverageMeasurement::CoverageMatrix.new(Numo::Int32[[5], [5], [5], [0]])
      m.record(0, 0, hit_count: 5, lines: [99, 100])
      m.record(1, 0, hit_count: 5, lines: [99, 101])
      m.record(2, 0, hit_count: 5, lines: [99, 102])
      # spec 3 has zero hit_count; no lines recorded
      m
    end

    let(:filter_common_code_index) do
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/models/foo.rb' => 0 },
        index_hash: { 0 => 'app/models/foo.rb' }
      )
    end

    let(:filter_common_spec_index) do
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: {
          'spec/foo_spec.rb:1' => 0,
          'spec/foo_spec.rb:2' => 1,
          'spec/foo_spec.rb:3' => 2,
          'spec/foo_spec.rb:4' => 3,
        },
        index_hash: {
          '0' => 'spec/foo_spec.rb:1',
          '1' => 'spec/foo_spec.rb:2',
          '2' => 'spec/foo_spec.rb:3',
          '3' => 'spec/foo_spec.rb:4',
        }
      )
    end

    let(:filter_common_measurement) do
      double('CM',
             coverage_matrix: filter_common_matrix,
             code_file_to_index: filter_common_code_index,
             spec_file_to_index: filter_common_spec_index)
    end

    def build_hunk_changeset(file_path, changed_lines_result)
      hunk = double('Hunk')
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return([file_path])
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).with(file_path).and_return([hunk])
      allow(changeset).to receive(:diff_hunks).and_return({ file_path => [hunk] })
      allow(Testsort::DiffOffsetAdjuster).to receive(:pure_insertion?).with([hunk]).and_return(false)
      allow(Testsort::DiffOffsetAdjuster).to receive(:changed_old_lines).with([hunk]).and_return(changed_lines_result)
      changeset
    end

    around do |example|
      original_ll = Testsort.configuration.line_level
      Testsort.configuration.line_level = true
      example.run
    ensure
      Testsort.configuration.line_level = original_ll
    end

    context 'when line_level_filter_common is true (default)' do
      around do |example|
        original = Testsort.configuration.line_level_filter_common
        Testsort.configuration.line_level_filter_common = true
        example.run
      ensure
        Testsort.configuration.line_level_filter_common = original
      end

      it 'suppresses common lines and produces no line-level match (all changed lines are common)' do
        # Only changed line is 99 which is covered by 3/4 specs → common → filtered out
        changeset = build_hunk_changeset('app/models/foo.rb', [99])
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, filter_common_measurement)
        # Common-filter removes line 99; informative_lines is empty → file-fallback fires
        # file-fallback returns specs 0,1,2 (those with coverage > 0)
        result = strategy.affected_example_indices
        # Result is via file-fallback, not line matching; they should still appear
        expect(result).to contain_exactly(0, 1, 2)
      end
    end

    context 'when line_level_filter_common is false' do
      around do |example|
        original = Testsort.configuration.line_level_filter_common
        Testsort.configuration.line_level_filter_common = false
        example.run
      ensure
        Testsort.configuration.line_level_filter_common = original
      end

      it 'includes common lines in matching — specs are matched via line intersection' do
        # Changed line 99 is "common" but filter is disabled, so it IS used for matching.
        # All three specs covering line 99 should be matched.
        changeset = build_hunk_changeset('app/models/foo.rb', [99])
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, filter_common_measurement)
        result = strategy.affected_example_indices
        expect(result).to contain_exactly(0, 1, 2)
      end

      it 'does NOT invoke filter_common_lines' do
        changeset = build_hunk_changeset('app/models/foo.rb', [99])
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, filter_common_measurement)
        expect(strategy).not_to receive(:filter_common_lines)
        strategy.affected_example_indices
      end
    end
  end

  # -------------------------------------------------------------------------
  # Flag: line_level_strength_sort
  # -------------------------------------------------------------------------
  # Setup: 2 specs × 1 file. Changed lines: [10, 11, 12, 13, 14].
  # Spec 0 (path_hash insertion order first) covers only [10] → strength 1.
  # Spec 1 covers [10,11,12,13,14] → strength 5.
  # With strength_sort=true: result is [1, 0] (strongest first).
  # With strength_sort=false: result is [0, 1] (insertion order = path_hash order).
  describe 'line_level_strength_sort flag' do
    let(:strength_matrix) do
      m = Testsort::CoverageMeasurement::CoverageMatrix.new(Numo::Int32[[5], [5]])
      m.record(0, 0, hit_count: 1, lines: [10])
      m.record(1, 0, hit_count: 5, lines: [10, 11, 12, 13, 14])
      m
    end

    let(:strength_code_index) do
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/models/bar.rb' => 0 },
        index_hash: { 0 => 'app/models/bar.rb' }
      )
    end

    let(:strength_spec_index) do
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: {
          'spec/bar_spec.rb:1' => 0,
          'spec/bar_spec.rb:2' => 1,
        },
        index_hash: {
          '0' => 'spec/bar_spec.rb:1',
          '1' => 'spec/bar_spec.rb:2',
        }
      )
    end

    let(:strength_measurement) do
      double('CM',
             coverage_matrix: strength_matrix,
             code_file_to_index: strength_code_index,
             spec_file_to_index: strength_spec_index)
    end

    def build_strength_changeset
      hunk = double('Hunk')
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(['app/models/bar.rb'])
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).with('app/models/bar.rb').and_return([hunk])
      allow(changeset).to receive(:diff_hunks).and_return({ 'app/models/bar.rb' => [hunk] })
      allow(Testsort::DiffOffsetAdjuster).to receive(:pure_insertion?).with([hunk]).and_return(false)
      # Changed lines [10,11,12,13,14] — neither is common (only 2 specs total, each covers them partially)
      allow(Testsort::DiffOffsetAdjuster).to receive(:changed_old_lines).with([hunk]).and_return([10, 11, 12, 13, 14])
      changeset
    end

    around do |example|
      original_ll = Testsort.configuration.line_level
      original_fc = Testsort.configuration.line_level_filter_common
      Testsort.configuration.line_level = true
      # Disable common filtering so all changed lines stay informative
      Testsort.configuration.line_level_filter_common = false
      example.run
    ensure
      Testsort.configuration.line_level = original_ll
      Testsort.configuration.line_level_filter_common = original_fc
    end

    context 'when line_level_strength_sort is true (default)' do
      around do |example|
        original = Testsort.configuration.line_level_strength_sort
        Testsort.configuration.line_level_strength_sort = true
        example.run
      ensure
        Testsort.configuration.line_level_strength_sort = original
      end

      it 'returns specs sorted by descending intersection strength — strongest spec first' do
        changeset = build_strength_changeset
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, strength_measurement)
        result = strategy.affected_example_indices
        # Spec 1 (strength 5) before spec 0 (strength 1)
        expect(result).to eq([1, 0])
      end
    end

    context 'when line_level_strength_sort is false' do
      around do |example|
        original = Testsort.configuration.line_level_strength_sort
        Testsort.configuration.line_level_strength_sort = false
        example.run
      ensure
        Testsort.configuration.line_level_strength_sort = original
      end

      it 'returns specs in insertion (path_hash iteration) order, not strength order' do
        changeset = build_strength_changeset
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, strength_measurement)
        result = strategy.affected_example_indices
        # path_hash insertion order: spec 0 first, then spec 1
        expect(result).to eq([0, 1])
      end
    end
  end

  # -------------------------------------------------------------------------
  # in_groups: true — round-robin distribution for parallel_rspec
  # -------------------------------------------------------------------------
  describe '#prioritized_spec_order(in_groups: true)' do
    around do |example|
      original = Testsort.configuration.line_level
      Testsort.configuration.line_level = true
      example.run
    ensure
      Testsort.configuration.line_level = original
    end

    def build_parallel_changeset(affected)
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(affected)
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).and_return([])
      allow(changeset).to receive(:diff_hunks).and_return({})
      allow(changeset).to receive(:spec_diff_hunks).and_return({})
      changeset
    end

    it 'returns an array of arrays (one per process)' do
      changeset = build_parallel_changeset(['app/models/user.rb'])
      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return('2')

      result = strategy.prioritized_spec_order(in_groups: true)
      expect(result).to be_an(Array)
      expect(result.all? { |g| g.is_a?(Array) }).to be true
    end

    it 'distributes specs in round-robin order across N groups' do
      # 4 specs in the flat priority list; 2 processes → 2 groups of 2
      # flat order (by coverage desc): user_spec:1 (10 hits), user_spec:2 (8 hits),
      # post_spec:1 (5 hits), other_spec:1 (0 hits)
      changeset = build_parallel_changeset(['app/models/user.rb', 'app/models/post.rb'])
      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return('2')

      result = strategy.prioritized_spec_order(in_groups: true)

      expect(result.length).to eq(2)
      # Every spec appears exactly once across all groups
      all_specs = result.flatten
      expect(all_specs.uniq.length).to eq(all_specs.length)
      expect(all_specs.length).to eq(4)
    end

    it 'places every other spec into alternate groups (round-robin interleave)' do
      changeset = build_parallel_changeset(['app/models/user.rb'])
      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return('2')

      result = strategy.prioritized_spec_order(in_groups: true)

      # Get the flat priority order from the same strategy via in_groups: false
      flat = strategy.prioritized_spec_order(in_groups: false)

      # Round-robin: even indices → group 0, odd indices → group 1
      expected_group0 = flat.each_with_index.select { |_, i| i.even? }.map(&:first)
      expected_group1 = flat.each_with_index.select { |_, i| i.odd? }.map(&:first)

      expect(result[0]).to eq(expected_group0)
      expect(result[1]).to eq(expected_group1)
    end

    it 'falls back to Etc.nprocessors when ENV var is unset' do
      changeset = build_parallel_changeset(['app/models/user.rb'])
      strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, measurement)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return(nil)

      result = strategy.prioritized_spec_order(in_groups: true)
      expect(result).to be_an(Array)
      expect(result.all? { |g| g.is_a?(Array) }).to be true
    end
  end

  # -------------------------------------------------------------------------
  # Flag: line_level_naive_order
  # -------------------------------------------------------------------------
  # Demonstrates the legacy path bypasses common-line filter.
  # Setup: 2 specs × 1 file. Changed line is 50, which is common (both specs
  # cover it → 2/2 = 100% > 50% threshold). Default mode: common filter
  # removes line 50 → file-fallback fires for this file → both specs returned
  # via fallback. Naive mode: no filter → both specs matched directly.
  # The distinction is visible because naive mode returns matched_examples
  # (line-matched) while default returns file_fallback_examples; the SET is
  # the same but we can verify naive mode doesn't call filter_common_lines.
  describe 'line_level_naive_order flag' do
    let(:naive_matrix) do
      m = Testsort::CoverageMeasurement::CoverageMatrix.new(Numo::Int32[[3], [3]])
      m.record(0, 0, hit_count: 3, lines: [50, 60])
      m.record(1, 0, hit_count: 3, lines: [50, 70])
      m
    end

    let(:naive_code_index) do
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/models/baz.rb' => 0 },
        index_hash: { 0 => 'app/models/baz.rb' }
      )
    end

    let(:naive_spec_index) do
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: {
          'spec/baz_spec.rb:1' => 0,
          'spec/baz_spec.rb:2' => 1,
        },
        index_hash: {
          '0' => 'spec/baz_spec.rb:1',
          '1' => 'spec/baz_spec.rb:2',
        }
      )
    end

    let(:naive_measurement) do
      double('CM',
             coverage_matrix: naive_matrix,
             code_file_to_index: naive_code_index,
             spec_file_to_index: naive_spec_index)
    end

    def build_naive_changeset
      hunk = double('Hunk')
      changeset = instance_double(Testsort::Changeset)
      allow(changeset).to receive(:affected).and_return(['app/models/baz.rb'])
      allow(changeset).to receive(:old_paths_by_new_path).and_return({})
      allow(changeset).to receive(:hunks_for).with('app/models/baz.rb').and_return([hunk])
      allow(changeset).to receive(:diff_hunks).and_return({ 'app/models/baz.rb' => [hunk] })
      allow(Testsort::DiffOffsetAdjuster).to receive(:pure_insertion?).with([hunk]).and_return(false)
      # Only changed line is 50, which is common (covered by both specs)
      allow(Testsort::DiffOffsetAdjuster).to receive(:changed_old_lines).with([hunk]).and_return([50])
      changeset
    end

    around do |example|
      original_ll = Testsort.configuration.line_level
      Testsort.configuration.line_level = true
      example.run
    ensure
      Testsort.configuration.line_level = original_ll
    end

    context 'when line_level_naive_order is false (default)' do
      around do |example|
        original = Testsort.configuration.line_level_naive_order
        Testsort.configuration.line_level_naive_order = false
        example.run
      ensure
        Testsort.configuration.line_level_naive_order = original
      end

      it 'invokes filter_common_lines (default path calls the filter)' do
        changeset = build_naive_changeset
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, naive_measurement)
        expect(strategy).to receive(:filter_common_lines).and_call_original
        strategy.affected_example_indices
      end
    end

    context 'when line_level_naive_order is true' do
      around do |example|
        original = Testsort.configuration.line_level_naive_order
        Testsort.configuration.line_level_naive_order = true
        example.run
      ensure
        Testsort.configuration.line_level_naive_order = original
      end

      it 'bypasses filter_common_lines entirely — uses legacy code path' do
        changeset = build_naive_changeset
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, naive_measurement)
        expect(strategy).not_to receive(:filter_common_lines)
        strategy.affected_example_indices
      end

      it 'matches specs covering the changed line without filtering' do
        changeset = build_naive_changeset
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, naive_measurement)
        result = strategy.affected_example_indices
        # Both specs cover line 50; naive mode returns both via matched_examples
        expect(result).to contain_exactly(0, 1)
      end

      it 'overrides line_level_filter_common and line_level_strength_sort settings' do
        # Even if both sub-flags are set, naive_order takes precedence
        original_fc = Testsort.configuration.line_level_filter_common
        original_ss = Testsort.configuration.line_level_strength_sort
        Testsort.configuration.line_level_filter_common = true
        Testsort.configuration.line_level_strength_sort = true

        changeset = build_naive_changeset
        strategy = Testsort::Prioritization::Strategies::Absolute.new(changeset, naive_measurement)
        expect(strategy).not_to receive(:filter_common_lines)
        result = strategy.affected_example_indices
        expect(result).to contain_exactly(0, 1)
      ensure
        Testsort.configuration.line_level_filter_common = original_fc
        Testsort.configuration.line_level_strength_sort = original_ss
      end
    end
  end
end
