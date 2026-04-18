# frozen_string_literal: true

describe Testsort::Prioritization::SpecList do
  let(:paths) { ['spec/a_spec.rb', 'spec/b_spec.rb', 'spec/c_spec.rb'] }
  subject(:spec_list) { described_class.new(paths) }

  describe '#sorted_by_times_covered' do
    it 'returns ALL specs sorted by times_covered descending' do
      spec_list[0] = 5
      spec_list[1] = 10
      spec_list[2] = 0

      expect(spec_list.sorted_by_times_covered).to eq([
        'spec/b_spec.rb',
        'spec/a_spec.rb',
        'spec/c_spec.rb',
      ])
    end

    it 'includes specs with zero coverage' do
      spec_list[0] = 3
      # spec_list[1] and [2] remain at 0

      result = spec_list.sorted_by_times_covered
      expect(result).to include('spec/b_spec.rb', 'spec/c_spec.rb')
      expect(result.length).to eq(3)
    end
  end

  describe '#select_times_covered_sorted' do
    it 'returns only specs with non-zero coverage, sorted descending' do
      spec_list[0] = 5
      spec_list[1] = 10
      spec_list[2] = 0

      expect(spec_list.select_times_covered_sorted).to eq([
        'spec/b_spec.rb',
        'spec/a_spec.rb',
      ])
    end

    it 'returns empty array when all specs have zero coverage' do
      expect(spec_list.select_times_covered_sorted).to eq([])
    end
  end

  describe '#count' do
    it 'returns the number of specs' do
      expect(spec_list.count).to eq(3)
    end
  end

  context 'with an empty path list' do
    subject(:spec_list) { described_class.new([]) }

    it 'returns empty for sorted_by_times_covered' do
      expect(spec_list.sorted_by_times_covered).to eq([])
    end

    it 'returns empty for select_times_covered_sorted' do
      expect(spec_list.select_times_covered_sorted).to eq([])
    end
  end
end
