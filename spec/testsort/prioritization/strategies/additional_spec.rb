# frozen_string_literal: true

describe Testsort::Prioritization::Strategies::Additional, :strategy do
  describe '#prioritized_spec_order' do
    it 'returns specs ordered by greedy marginal coverage' do
      strategy = described_class.new(changeset, measurement)
      result = strategy.prioritized_spec_order

      # Greedy: pick spec with highest coverage, then next spec covering most new files, etc.
      # spec_c covers file 0 only, spec_b covers file 1 (new), then remaining specs appended
      expect(result).to eq([
        'spec/c_spec.rb',
        'spec/b_spec.rb',
        'spec/d_spec.rb',
        'spec/a_spec.rb',
        'spec/a_spec.rb',
      ])
    end

    context 'with empty changeset' do
      it 'returns full file list unprioritized' do
        strategy = described_class.new(empty_changeset, measurement)
        result = strategy.prioritized_spec_order

        expect(result).to eq(['spec/a_spec.rb', 'spec/b_spec.rb', 'spec/c_spec.rb', 'spec/d_spec.rb'])
      end
    end
  end
end
