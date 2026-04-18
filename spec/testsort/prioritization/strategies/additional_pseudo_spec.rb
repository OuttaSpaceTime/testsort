# frozen_string_literal: true

describe Testsort::Prioritization::Strategies::AdditionalPseudo, :strategy do
  describe '#prioritized_spec_order' do
    it 'returns specs ordered by bin-sorted coverage of affected files' do
      strategy = described_class.new(changeset, measurement)
      result = strategy.prioritized_spec_order

      # Specs are grouped by number of affected files covered (bins),
      # then sorted by total coverage within each bin
      expect(result).to eq([
        'spec/c_spec.rb',
        'spec/d_spec.rb',
        'spec/b_spec.rb',
      ])
    end

    context 'with empty changeset' do
      it 'returns full file list unprioritized' do
        strategy = described_class.new(empty_changeset, measurement)
        result = strategy.prioritized_spec_order

        expect(result).to eq(['spec/a_spec.rb', 'spec/b_spec.rb', 'spec/c_spec.rb', 'spec/d_spec.rb'])
      end
    end

    context 'with in_groups: true' do
      it 'returns nested arrays for parallel execution' do
        strategy = described_class.new(changeset, measurement)
        result = strategy.prioritized_spec_order(in_groups: true)

        expect(result).to be_an(Array)
        expect(result.first).to be_an(Array)
        expect(result.flatten).to include('spec/c_spec.rb', 'spec/b_spec.rb')
      end
    end
  end
end
