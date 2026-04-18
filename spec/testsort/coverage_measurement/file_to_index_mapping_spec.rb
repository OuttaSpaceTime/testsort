# frozen_string_literal: true

describe Testsort::CoverageMeasurement::FileToIndexMapping do
  subject(:mapping) { described_class.new }

  describe '#insert' do
    it 'creates a bidirectional mapping' do
      mapping.insert('app/models/user.rb')

      expect(mapping['app/models/user.rb']).to eq(0)
      expect(mapping[0]).to eq('app/models/user.rb')
    end

    it 'increments file_index for each new entry' do
      mapping.insert('app/models/user.rb')
      mapping.insert('app/models/post.rb')

      expect(mapping['app/models/user.rb']).to eq(0)
      expect(mapping['app/models/post.rb']).to eq(1)
      expect(mapping.file_index).to eq(1)
    end

    it 'sets has_new_entries to true for new paths' do
      mapping.insert('app/models/user.rb')
      expect(mapping.has_new_entries).to eq(true)
    end

    it 'is a no-op for duplicate paths' do
      mapping.insert('app/models/user.rb')
      mapping.insert('app/models/user.rb')

      expect(mapping.has_new_entries).to eq(false)
      expect(mapping.file_index).to eq(0)
      expect(mapping.count).to eq(1)
    end
  end

  describe '#[]' do
    before do
      mapping.insert('app/models/user.rb')
    end

    it 'returns index when given a string key' do
      expect(mapping['app/models/user.rb']).to eq(0)
    end

    it 'returns path when given an integer key' do
      expect(mapping[0]).to eq('app/models/user.rb')
    end
  end

  describe '#exclude?' do
    it 'returns true for unknown paths' do
      expect(mapping.exclude?('unknown.rb')).to eq(true)
    end

    it 'returns false for known paths' do
      mapping.insert('app/models/user.rb')
      expect(mapping.exclude?('app/models/user.rb')).to eq(false)
    end
  end

  describe '#include?' do
    it 'returns false for unknown paths' do
      expect(mapping.include?('unknown.rb')).to eq(false)
    end

    it 'returns true for known paths' do
      mapping.insert('app/models/user.rb')
      expect(mapping.include?('app/models/user.rb')).to eq(true)
    end
  end

  describe '#file_list' do
    it 'returns all mapped paths' do
      mapping.insert('spec/a_spec.rb')
      mapping.insert('spec/b_spec.rb')

      expect(mapping.file_list).to eq(['spec/a_spec.rb', 'spec/b_spec.rb'])
    end
  end

  describe '#count' do
    it 'returns the number of entries' do
      mapping.insert('a.rb')
      mapping.insert('b.rb')

      expect(mapping.count).to eq(2)
    end
  end

  describe '#fetch_specs' do
    it 'returns paths for given index keys' do
      mapping.insert('spec/a_spec.rb')
      mapping.insert('spec/b_spec.rb')
      mapping.insert('spec/c_spec.rb')

      expect(mapping.fetch_specs([0, 2])).to eq(['spec/a_spec.rb', 'spec/c_spec.rb'])
    end
  end

  describe '#empty?' do
    it 'returns true when no entries exist' do
      expect(mapping.empty?).to eq(true)
    end

    it 'returns false after insert' do
      mapping.insert('a.rb')
      expect(mapping.empty?).to eq(false)
    end
  end

  describe 'initializing with existing data' do
    it 'restores from path_hash and index_hash' do
      restored = described_class.new(
        path_hash: { 'a.rb' => 0, 'b.rb' => 1 },
        index_hash: { 0 => 'a.rb', 1 => 'b.rb' }
      )

      expect(restored['a.rb']).to eq(0)
      expect(restored[1]).to eq('b.rb')
      expect(restored.file_index).to eq(1)
    end
  end
end
