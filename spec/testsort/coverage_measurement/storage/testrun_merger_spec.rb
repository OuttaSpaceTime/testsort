# frozen_string_literal: true

describe Testsort::CoverageMeasurement::Storage::TestrunMerger do
  let(:original_line_level) { Testsort.configuration.line_level }

  before { Testsort.configuration.line_level = true }
  after { Testsort.configuration.line_level = original_line_level }

  def build_measurement(specs:, files:, matrix:, lines: {})
    m = Testsort::CoverageMeasurement.new
    m.instance_variable_set(:@spec_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: specs.each_with_index.to_h,
        index_hash: specs.each_with_index.map { |s, i| [i, s] }.to_h
      ))
    m.instance_variable_set(:@code_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: files.each_with_index.to_h,
        index_hash: files.each_with_index.map { |f, i| [i, f] }.to_h
      ))
    cm = Testsort::CoverageMeasurement::CoverageMatrix.new(matrix)
    lines.each do |(spec_idx, file_idx), line_arr|
      cm.record(spec_idx, file_idx, hit_count: matrix[spec_idx, file_idx], lines: line_arr)
    end
    m.instance_variable_set(:@coverage_matrix, cm)
    m
  end

  describe '#merge_coverage_results' do
    it 'REPLACEs ground-truth line vectors for a re-measured spec (not union)' do
      ground_truth = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[2]],
        lines: { [0, 0] => [5] }
      )
      new_measurement = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[3]],
        lines: { [0, 0] => [10] }
      )

      merger = described_class.new(ground_truth, new_measurement)
      merged = merger.merge_coverage_results

      # Replace semantics: line 5 (from old ground truth) must NOT appear;
      # only line 10 (from new run) should be present.
      expect(merged.coverage_matrix.lines_for(0, 0)).to eq([10])
      expect(merged.coverage_matrix[0, 0]).to eq(3)
    end

    it 'REPLACEs with empty file coverage when re-measured spec no longer covers a file' do
      ground_truth = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[5]],
        lines: { [0, 0] => [1, 2, 3] }
      )
      new_measurement = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/b.rb'],
        matrix: Numo::Int32[[2]],
        lines: { [0, 0] => [7] }
      )

      merger = described_class.new(ground_truth, new_measurement)
      merged = merger.merge_coverage_results

      gt_spec_idx = merged.spec_file_to_index['spec/a_spec.rb']
      gt_file_idx = merged.code_file_to_index['app/a.rb']

      # The spec was re-measured but didn't cover app/a.rb — its old row was
      # cleared, so the cell must be 0 and line vector must be gone.
      expect(merged.coverage_matrix[gt_spec_idx, gt_file_idx]).to eq(0)
      expect(merged.coverage_matrix.lines_for(gt_spec_idx, gt_file_idx)).to be_nil
    end

    it 'preserves ground-truth-only entries not present in the new run' do
      ground_truth = build_measurement(
        specs: ['spec/a_spec.rb', 'spec/b_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[2], [7]],
        lines: { [0, 0] => [1, 2], [1, 0] => [50, 51] }
      )
      new_measurement = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[3]],
        lines: { [0, 0] => [3] }
      )

      merger = described_class.new(ground_truth, new_measurement)
      merged = merger.merge_coverage_results

      gt_spec_idx = merged.spec_file_to_index['spec/b_spec.rb']
      # spec/b_spec.rb was NOT in the new run — its row must be untouched.
      expect(merged.coverage_matrix.lines_for(gt_spec_idx, 0)).to eq([50, 51])
    end

    it 'appends a new spec from the new run that was not in ground truth' do
      ground_truth = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[1]],
        lines: { [0, 0] => [10] }
      )
      new_measurement = build_measurement(
        specs: ['spec/new_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[4]],
        lines: { [0, 0] => [99] }
      )

      merger = described_class.new(ground_truth, new_measurement)
      merged = merger.merge_coverage_results

      new_gt_spec_idx = merged.spec_file_to_index['spec/new_spec.rb']
      gt_file_idx = merged.code_file_to_index['app/a.rb']
      expect(new_gt_spec_idx).not_to be_nil
      expect(merged.coverage_matrix[new_gt_spec_idx, gt_file_idx]).to eq(4)
      expect(merged.coverage_matrix.lines_for(new_gt_spec_idx, gt_file_idx)).to eq([99])
    end
  end
end
