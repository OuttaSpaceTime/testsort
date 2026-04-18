# frozen_string_literal: true

describe Testsort::Prioritization::Strategies::Absolute, :strategy do
  describe '#prioritized_spec_order' do
    it 'returns all specs sorted by total coverage of affected files descending' do
      # Affected files: index 0 and 1
      # Sums: spec0=5+3=8, spec1=0+2=2, spec2=4+0=4, spec3=0+0=0
      strategy = described_class.new(changeset, measurement)
      result = strategy.prioritized_spec_order

      expect(result).to eq([
        'spec/a_spec.rb',
        'spec/c_spec.rb',
        'spec/b_spec.rb',
        'spec/d_spec.rb',
      ])
    end

    context 'with empty changeset' do
      it 'returns all specs (all with zero coverage)' do
        strategy = described_class.new(empty_changeset, measurement)
        result = strategy.prioritized_spec_order

        expect(result.length).to eq(4)
      end
    end

    context 'with single affected file' do
      let(:affected_files) { ['app/models/post.rb'] }

      it 'ranks by coverage of that file only' do
        # Column 1 only: spec0=3, spec1=2, spec2=0, spec3=0
        strategy = described_class.new(changeset, measurement)
        result = strategy.prioritized_spec_order

        expect(result.first).to eq('spec/a_spec.rb')
        expect(result[1]).to eq('spec/b_spec.rb')
      end
    end
  end

  describe '#select_covered_spec_list' do
    it 'returns only specs with non-zero coverage of affected files' do
      strategy = described_class.new(changeset, measurement)
      result = strategy.select_covered_spec_list

      expect(result).to eq([
        'spec/a_spec.rb',
        'spec/c_spec.rb',
        'spec/b_spec.rb',
      ])
      expect(result).not_to include('spec/d_spec.rb')
    end
  end
end
