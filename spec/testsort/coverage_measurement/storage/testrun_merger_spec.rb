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
    it 'UNIONs line vectors for the same (spec, file) pair across runs (bug fix)' do
      ground_truth = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[2]],
        lines: { [0, 0] => [10, 11] }
      )
      new_measurement = build_measurement(
        specs: ['spec/a_spec.rb'],
        files: ['app/a.rb'],
        matrix: Numo::Int32[[3]],
        lines: { [0, 0] => [11, 20, 21] }
      )

      merger = described_class.new(ground_truth, new_measurement)
      merged = merger.merge_coverage_results

      expect(merged.coverage_matrix.lines_for(0, 0)).to eq([10, 11, 20, 21])
      # hit counts should be summed
      expect(merged.coverage_matrix[0, 0]).to eq(5)
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
      expect(merged.coverage_matrix.lines_for(gt_spec_idx, 0)).to eq([50, 51])
    end
  end
end
