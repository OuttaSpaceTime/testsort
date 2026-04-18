# frozen_string_literal: true

describe Testsort::CoverageMeasurement::CoverageMatrix do
  describe 'initialization' do
    it 'defaults to an empty matrix' do
      matrix = described_class.new
      expect(matrix.shape).to eq([0, 0])
    end

    it 'wraps a provided Numo array' do
      array = Numo::Int32[[1, 2], [3, 4]]
      matrix = described_class.new(array)
      expect(matrix.shape).to eq([2, 2])
    end
  end

  describe '#new_row' do
    it 'adds a row to an empty matrix' do
      matrix = described_class.new
      matrix.new_row(0, 3)
      expect(matrix.shape).to eq([1, 3])
    end

    it 'inserts a row into an existing matrix' do
      matrix = described_class.new(Numo::Int32[[1, 2, 3]])
      matrix.new_row(1, 3)
      expect(matrix.shape).to eq([2, 3])
      expect(matrix[1, 0]).to eq(0)
    end
  end

  describe '#new_column' do
    it 'inserts a column into the matrix' do
      matrix = described_class.new(Numo::Int32[[1, 2], [3, 4]])
      matrix.new_column(1, 2)
      expect(matrix.shape).to eq([2, 3])
      expect(matrix[0, 1]).to eq(0)
    end
  end

  describe '#[] and #[]=' do
    let(:matrix) { described_class.new(Numo::Int32[[0, 0], [0, 0]]) }

    it 'reads and writes individual cells' do
      matrix[0, 1] = 42
      expect(matrix[0, 1]).to eq(42)
    end
  end

  describe '#+' do
    it 'increments a cell value' do
      matrix = described_class.new(Numo::Int32[[5, 0], [0, 0]])
      matrix.+(0, 0, 3)
      expect(matrix[0, 0]).to eq(8)
    end
  end

  describe '#times_covered_by_spec' do
    let(:matrix) do
      described_class.new(Numo::Int32[
        [5, 3, 0],
        [0, 2, 1],
        [4, 0, 0],
      ])
    end

    it 'sums coverage across specified file indices per spec' do
      result = matrix.times_covered_by_spec([0, 1])
      expect(result.to_a).to eq([8, 2, 4])
    end

    it 'handles a single file index' do
      result = matrix.times_covered_by_spec([2])
      expect(result.to_a).to eq([0, 1, 0])
    end

    it 'returns nil on ShapeError' do
      # ShapeError occurs when file_indices produces mismatched shapes
      # e.g. empty array after filtering
      allow(matrix.coverage_matrix).to receive(:[]).and_raise(Numo::NArray::ShapeError)
      result = matrix.times_covered_by_spec([0])
      expect(result).to be_nil
    end
  end

  describe '#slice_by_files' do
    let(:matrix) do
      described_class.new(Numo::Int32[
        [5, 3, 0],
        [0, 2, 1],
        [4, 0, 0],
      ])
    end

    it 'returns a submatrix for specified file indices' do
      result = matrix.slice_by_files([1])
      expect(result.to_a).to eq([[3], [2], [0]])
    end

    it 'returns full matrix when file_indices is empty' do
      result = matrix.slice_by_files([])
      expect(result.shape).to eq([3, 3])
    end
  end

  describe '#record' do
    it 'sets the hit count (overwrite)' do
      matrix = described_class.new(Numo::Int32[[5, 0], [0, 0]])
      matrix.record(0, 0, hit_count: 3)
      expect(matrix[0, 0]).to eq(3)
    end

    it 'stores lines for the (spec, file) pair when lines given' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.record(0, 1, hit_count: 2, lines: [10, 11, 15])
      expect(matrix.lines_for(0, 1)).to eq([10, 11, 15])
    end

    it 'overwrites previously stored lines for the same pair' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.record(0, 1, hit_count: 2, lines: [10, 11])
      matrix.record(0, 1, hit_count: 4, lines: [30, 31])
      expect(matrix.lines_for(0, 1)).to eq([30, 31])
      expect(matrix[0, 1]).to eq(4)
    end

    it 'does not create a lines entry when lines is nil' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.record(0, 1, hit_count: 2)
      expect(matrix.lines_for(0, 1)).to be_nil
    end
  end

  describe '#union_record' do
    it 'sums hit counts' do
      matrix = described_class.new(Numo::Int32[[5, 0], [0, 0]])
      matrix.union_record(0, 0, hit_count: 3)
      expect(matrix[0, 0]).to eq(8)
    end

    it 'unions line arrays (bug fix: must not overwrite)' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.record(0, 0, hit_count: 2, lines: [10, 11])
      matrix.union_record(0, 0, hit_count: 3, lines: [11, 20, 21])
      expect(matrix.lines_for(0, 0)).to eq([10, 11, 20, 21])
      expect(matrix[0, 0]).to eq(5)
    end

    it 'sorts the union result' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.record(0, 0, hit_count: 1, lines: [30, 5])
      matrix.union_record(0, 0, hit_count: 1, lines: [15, 1])
      expect(matrix.lines_for(0, 0)).to eq([1, 5, 15, 30])
    end

    it 'seeds lines when no prior entry exists' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.union_record(0, 0, hit_count: 2, lines: [4, 2])
      expect(matrix.lines_for(0, 0)).to eq([2, 4])
    end
  end

  describe '#lines_for' do
    it 'returns nil for pairs never recorded' do
      matrix = described_class.new(Numo::Int32[[0, 0]])
      expect(matrix.lines_for(0, 0)).to be_nil
    end
  end

  describe '#lines_as_json_data and #load_lines_from_json_data' do
    it 'round-trips line data' do
      matrix = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      matrix.record(0, 1, hit_count: 1, lines: [22, 10, 15])
      matrix.record(1, 0, hit_count: 1, lines: [5, 3, 8])

      data = matrix.lines_as_json_data

      restored = described_class.new(Numo::Int32[[0, 0], [0, 0]])
      restored.load_lines_from_json_data(data)

      expect(restored.lines_for(0, 1)).to eq([10, 15, 22])
      expect(restored.lines_for(1, 0)).to eq([3, 5, 8])
    end

    it 'handles nil data gracefully' do
      matrix = described_class.new(Numo::Int32[[0, 0]])
      matrix.load_lines_from_json_data(nil)
      expect(matrix.lines_for(0, 0)).to be_nil
    end
  end

  describe '#to_oneshot_lines' do
    it 'clamps all non-zero values to 1' do
      matrix = described_class.new(Numo::Int32[[5, 0, 3], [0, 0, 1]])
      matrix.to_oneshot_lines
      expect(matrix[0, 0]).to eq(1)
      expect(matrix[0, 1]).to eq(0)
      expect(matrix[0, 2]).to eq(1)
      expect(matrix[1, 2]).to eq(1)
    end
  end
end
