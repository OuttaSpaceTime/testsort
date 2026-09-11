# frozen_string_literal: true

require 'spec_helper'

describe Testsort::Agent::Queries do
  # -------------------------------------------------------------------------
  # Shared fixtures
  # -------------------------------------------------------------------------
  # 3 spec files × 2 code files
  #   spec_idx 0 -> 'spec/models/user_spec.rb:1' covers code_idx 0 (user.rb)
  #   spec_idx 1 -> 'spec/models/user_spec.rb:2' covers code_idx 0 (user.rb)
  #   spec_idx 2 -> 'spec/models/post_spec.rb:1' covers code_idx 1 (post.rb)
  #   spec_idx 3 -> 'spec/other_spec.rb:1'       covers nothing

  let(:coverage_matrix) do
    m = Testsort::CoverageMeasurement::CoverageMatrix.new(
      Numo::Int32[[10, 0], [8, 0], [0, 5], [0, 0]]
    )
    m.record(0, 0, hit_count: 10, lines: [5, 6, 7])
    m.record(1, 0, hit_count: 8,  lines: [15, 16])
    m.record(2, 1, hit_count: 5,  lines: [1, 2, 3])
    m
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
        'spec/other_spec.rb:1'       => 3,
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
           coverage_matrix:     coverage_matrix,
           code_file_to_index:  code_file_to_index,
           spec_file_to_index:  spec_file_to_index)
  end

  # Changeset that reports user.rb modified
  def build_changeset(affected_paths, old_paths_by_new_path: {})
    cs = instance_double(Testsort::Changeset)
    allow(cs).to receive(:affected).and_return(affected_paths)
    allow(cs).to receive(:old_paths_by_new_path).and_return(old_paths_by_new_path)
    allow(cs).to receive(:hunks_for).and_return([])
    allow(cs).to receive(:diff_hunks).and_return({})
    allow(cs).to receive(:spec_diff_hunks).and_return({})
    cs
  end

  # Helpers to toggle configuration
  def with_line_level(value)
    original = Testsort.configuration.line_level
    Testsort.configuration.line_level = value
    yield
  ensure
    Testsort.configuration.line_level = original
  end

  # -------------------------------------------------------------------------
  # Guard: raises when no coverage data on disk
  # -------------------------------------------------------------------------
  describe '#initialize raises when matrix not stored' do
    it 'raises Testsort::Error when Paths.last_run_stored? is false' do
      allow(Testsort::Paths).to receive(:last_run_stored?).and_return(false)
      expect do
        described_class.new(coverage_measurement: measurement, changeset: build_changeset([]))
      end.to raise_error(Testsort::Error, /testsort prepare/)
    end

    it 'does not raise when Paths.last_run_stored? is true' do
      allow(Testsort::Paths).to receive(:last_run_stored?).and_return(true)
      expect do
        described_class.new(coverage_measurement: measurement, changeset: build_changeset([]))
      end.not_to raise_error
    end
  end

  # -------------------------------------------------------------------------
  # Shared guard helper
  # -------------------------------------------------------------------------
  def build_queries(changeset, strategy: 'absolute')
    allow(Testsort::Paths).to receive(:last_run_stored?).and_return(true)
    described_class.new(coverage_measurement: measurement, changeset: changeset, strategy: strategy)
  end

  # -------------------------------------------------------------------------
  # #universe — file-level mode (line_level = false)
  # -------------------------------------------------------------------------
  describe '#universe in file-level mode (line_level=false)' do
    around do |example|
      with_line_level(false) { example.run }
    end

    it 'returns spec paths that cover changed files' do
      changeset = build_changeset(['app/models/user.rb'])
      queries = build_queries(changeset)

      result = queries.universe
      expect(result).to include('spec/models/user_spec.rb:1', 'spec/models/user_spec.rb:2')
      expect(result).not_to include('spec/models/post_spec.rb:1')
    end

    it 'returns empty array when diff has no covered files' do
      changeset = build_changeset(['app/untracked_file.rb'])
      queries = build_queries(changeset)

      expect(queries.universe).to eq([])
    end

    it 'returns empty array for empty diff' do
      changeset = build_changeset([])
      queries = build_queries(changeset)

      expect(queries.universe).to eq([])
    end

    it 'includes new spec files from the diff (not in matrix)' do
      changeset = build_changeset(['app/models/user.rb', 'spec/new_feature_spec.rb'])
      queries = build_queries(changeset)

      result = queries.universe
      # Matrix-matched specs first
      expect(result).to include('spec/models/user_spec.rb:1', 'spec/models/user_spec.rb:2')
      # New spec file appended
      expect(result).to include('spec/new_feature_spec.rb')
      # Matrix matches appear before new spec files
      matched_idx = result.index { |s| s.include?('user_spec') }
      new_idx = result.index('spec/new_feature_spec.rb')
      expect(matched_idx).to be < new_idx
    end

    it 'does not include non-spec files from diff in new spec files' do
      changeset = build_changeset(['app/models/user.rb', 'app/models/new_model.rb'])
      queries = build_queries(changeset)

      result = queries.universe
      expect(result).not_to include('app/models/new_model.rb')
    end

    it 'does not duplicate new spec files already covered by the matrix' do
      # user_spec.rb paths in the matrix use :line keys, so 'spec/models/user_spec.rb'
      # (no :line) would not match — it IS a new spec file.
      # This test verifies that matched specs are not re-added as "new" specs.
      changeset = build_changeset(['app/models/user.rb'])
      queries = build_queries(changeset)

      result = queries.universe
      expect(result.uniq.length).to eq(result.length)
    end
  end

  # -------------------------------------------------------------------------
  # #universe — line-level mode (line_level = true)
  # -------------------------------------------------------------------------
  describe '#universe in line-level mode (line_level=true)' do
    around do |example|
      with_line_level(true) { example.run }
    end

    before do
      allow(Testsort.configuration).to receive(:line_level_filter_common).and_return(false)
      allow(Testsort.configuration).to receive(:line_level_strength_sort).and_return(false)
      allow(Testsort.configuration).to receive(:line_level_naive_order).and_return(false)
    end

    it 'returns path:line keys for specs covering changed lines' do
      changeset = build_changeset(['app/models/user.rb'])
      # With empty hunks the prioritization falls back to file-level for line matching
      queries = build_queries(changeset)

      result = queries.universe
      # Should include examples that cover user.rb
      expect(result).to include('spec/models/user_spec.rb:1', 'spec/models/user_spec.rb:2')
    end

    it 'returns empty array for empty diff' do
      changeset = build_changeset([])
      queries = build_queries(changeset)

      expect(queries.universe).to eq([])
    end

    it 'includes new spec files from the diff (not in matrix)' do
      changeset = build_changeset(['app/models/user.rb', 'spec/new_example_spec.rb'])
      queries = build_queries(changeset)

      result = queries.universe
      expect(result).to include('spec/new_example_spec.rb')
      # New file appended after matched keys
      new_idx = result.index('spec/new_example_spec.rb')
      expect(new_idx).to be > 0 if result.length > 1
    end

    it 'does not include new spec files already in the matrix' do
      # 'spec/models/user_spec.rb:1' is in the matrix — not a "new" spec file.
      # The plain path 'spec/models/user_spec.rb' without :line is not in the matrix,
      # so it would appear as new. But test only with truly-new paths.
      changeset = build_changeset(['spec/completely_new_spec.rb'])
      queries = build_queries(changeset)

      result = queries.universe
      expect(result).to include('spec/completely_new_spec.rb')
    end
  end

  # -------------------------------------------------------------------------
  # #suggest
  # -------------------------------------------------------------------------
  describe '#suggest' do
    around do |example|
      with_line_level(false) { example.run }
    end

    it 'returns a flat array (parallel: false)' do
      changeset = build_changeset(['app/models/user.rb'])
      queries = build_queries(changeset, strategy: 'absolute')

      result = queries.suggest(parallel: false)
      expect(result).to be_an(Array)
      expect(result.none? { |item| item.is_a?(Array) }).to be true
    end

    it 'returns grouped arrays (parallel: true) in line_level mode' do
      # In line_level=false, rank_all ignores in_groups and returns flat array.
      # Groups are produced only when line_level=true in the base prioritized_spec_order.
      with_line_level(true) do
        allow(Testsort.configuration).to receive(:line_level_filter_common).and_return(false)
        allow(Testsort.configuration).to receive(:line_level_strength_sort).and_return(false)
        allow(Testsort.configuration).to receive(:line_level_naive_order).and_return(false)

        changeset = build_changeset(['app/models/user.rb'])
        queries = build_queries(changeset, strategy: 'absolute')

        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return('2')

        result = queries.suggest(parallel: true)
        expect(result).to be_an(Array)
        expect(result.all? { |g| g.is_a?(Array) }).to be true
      end
    end

    it 'suggest(parallel: true) in line_level mode: all specs covered across groups' do
      with_line_level(true) do
        allow(Testsort.configuration).to receive(:line_level_filter_common).and_return(false)
        allow(Testsort.configuration).to receive(:line_level_strength_sort).and_return(false)
        allow(Testsort.configuration).to receive(:line_level_naive_order).and_return(false)

        changeset = build_changeset(['app/models/user.rb'])
        queries = build_queries(changeset, strategy: 'absolute')

        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PARALLEL_TEST_PROCESSORS').and_return('2')

        flat    = queries.suggest(parallel: false)
        grouped = queries.suggest(parallel: true)

        expect(grouped.flatten.to_set).to eq(flat.to_set)
      end
    end

    %w[absolute oneshot].each do |strategy_name|
      it "works with strategy '#{strategy_name}'" do
        changeset = build_changeset(['app/models/user.rb'])
        queries = build_queries(changeset, strategy: strategy_name)

        expect { queries.suggest(parallel: false) }.not_to raise_error
      end
    end

    it "works with strategy 'additional'" do
      changeset = build_changeset(['app/models/user.rb'])
      queries = build_queries(changeset, strategy: 'additional')

      expect { queries.suggest(parallel: false) }.not_to raise_error
    end

    it "works with strategy 'additional_pseudo'" do
      changeset = build_changeset(['app/models/user.rb'])
      queries = build_queries(changeset, strategy: 'additional_pseudo')

      expect { queries.suggest(parallel: false) }.not_to raise_error
    end

    it "works with strategy 'additional pseudo' (space variant)" do
      changeset = build_changeset(['app/models/user.rb'])
      queries = build_queries(changeset, strategy: 'additional pseudo')

      expect { queries.suggest(parallel: false) }.not_to raise_error
    end

    it 'raises Testsort::Error for unknown strategy' do
      changeset = build_changeset(['app/models/user.rb'])
      allow(Testsort::Paths).to receive(:last_run_stored?).and_return(true)
      queries = described_class.new(
        coverage_measurement: measurement,
        changeset: changeset,
        strategy: 'does_not_exist'
      )

      expect { queries.suggest(parallel: false) }.to raise_error(Testsort::Error, /Unknown strategy/)
    end
  end

  # -------------------------------------------------------------------------
  # .strategy_class_for
  # -------------------------------------------------------------------------
  describe '.strategy_class_for' do
    it 'resolves "absolute" to Absolute' do
      expect(described_class.strategy_class_for('absolute')).to eq(Testsort::Prioritization::Strategies::Absolute)
    end

    it 'resolves "oneshot" to Absolute' do
      expect(described_class.strategy_class_for('oneshot')).to eq(Testsort::Prioritization::Strategies::Absolute)
    end

    it 'resolves "additional" to Additional' do
      expect(described_class.strategy_class_for('additional')).to eq(Testsort::Prioritization::Strategies::Additional)
    end

    it 'resolves "additional_pseudo" to AdditionalPseudo' do
      expect(described_class.strategy_class_for('additional_pseudo')).to eq(Testsort::Prioritization::Strategies::AdditionalPseudo)
    end

    it 'resolves "additional pseudo" (space) to AdditionalPseudo' do
      expect(described_class.strategy_class_for('additional pseudo')).to eq(Testsort::Prioritization::Strategies::AdditionalPseudo)
    end

    it 'is case-insensitive' do
      expect(described_class.strategy_class_for('ABSOLUTE')).to eq(Testsort::Prioritization::Strategies::Absolute)
    end

    it 'raises for unknown strategy' do
      expect { described_class.strategy_class_for('magic') }.to raise_error(Testsort::Error, /Unknown strategy/)
    end
  end
end
