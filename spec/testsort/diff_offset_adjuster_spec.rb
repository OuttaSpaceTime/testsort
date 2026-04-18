# frozen_string_literal: true

describe Testsort::DiffOffsetAdjuster do
  # Helper to create mock hunk objects matching Rugged::Diff::Hunk interface
  def mock_hunk(old_start:, old_lines:, new_start:, new_lines:, lines: [])
    hunk = double('Hunk',
                  old_start: old_start,
                  old_lines: old_lines,
                  new_start: new_start,
                  new_lines: new_lines)
    allow(hunk).to receive(:each_line) do |&block|
      if block
        lines.each(&block)
      else
        lines.each
      end
    end
    hunk
  end

  def mock_line(old_lineno:, new_lineno: nil, origin:)
    double('Line', old_lineno: old_lineno, new_lineno: new_lineno, line_origin: origin)
  end

  describe '.adjust_lines' do
    it 'returns lines unchanged when no hunks' do
      expect(described_class.adjust_lines([10, 20, 30], [])).to eq([10, 20, 30])
    end

    it 'shifts lines after an insertion' do
      # 5 new lines inserted at line 10
      hunk = mock_hunk(old_start: 10, old_lines: 0, new_start: 10, new_lines: 5)
      result = described_class.adjust_lines([5, 15, 20], [hunk])

      expect(result).to include(5)      # before hunk, unchanged
      expect(result).to include(20)     # 15 + 5 offset
      expect(result).to include(25)     # 20 + 5 offset
    end

    it 'shifts lines after a deletion' do
      # 3 lines deleted starting at line 10
      lines = [
        mock_line(old_lineno: 10, origin: :deletion),
        mock_line(old_lineno: 11, origin: :deletion),
        mock_line(old_lineno: 12, origin: :deletion),
      ]
      hunk = mock_hunk(old_start: 10, old_lines: 3, new_start: 10, new_lines: 0, lines: lines)
      result = described_class.adjust_lines([5, 15, 20], [hunk])

      expect(result).to include(5)      # before hunk, unchanged
      expect(result).to include(12)     # 15 - 3 offset
      expect(result).to include(17)     # 20 - 3 offset
    end

    it 'removes deleted lines from results' do
      lines = [
        mock_line(old_lineno: 10, origin: :deletion),
      ]
      hunk = mock_hunk(old_start: 10, old_lines: 1, new_start: 10, new_lines: 0, lines: lines)
      result = described_class.adjust_lines([10], [hunk])

      expect(result).to be_empty
    end

    it 'handles multiple hunks with cumulative offsets' do
      # First hunk: +5 at line 10
      hunk1 = mock_hunk(old_start: 10, old_lines: 0, new_start: 10, new_lines: 5)
      # Second hunk: +3 at line 30
      hunk2 = mock_hunk(old_start: 30, old_lines: 0, new_start: 35, new_lines: 3)

      result = described_class.adjust_lines([5, 20, 40], [hunk1, hunk2])

      expect(result).to include(5)      # before both hunks
      expect(result).to include(25)     # 20 + 5
      expect(result).to include(48)     # 40 + 5 + 3
    end
  end

  describe '.adjust_spec_key' do
    it 'adjusts the line number in a spec key' do
      hunk = mock_hunk(old_start: 10, old_lines: 0, new_start: 10, new_lines: 20)
      result = described_class.adjust_spec_key('spec/models/user_spec.rb:50', [hunk])

      expect(result).to eq('spec/models/user_spec.rb:70')
    end

    it 'returns original key if path has no colon' do
      result = described_class.adjust_spec_key('spec/models/user_spec.rb', [])
      expect(result).to eq('spec/models/user_spec.rb')
    end

    it 'returns nil when the line was deleted' do
      lines = [mock_line(old_lineno: 50, origin: :deletion)]
      hunk = mock_hunk(old_start: 50, old_lines: 1, new_start: 50, new_lines: 0, lines: lines)

      result = described_class.adjust_spec_key('spec/user_spec.rb:50', [hunk])
      expect(result).to be_nil
    end

    it 'returns key unchanged when there is no colon' do
      expect(described_class.adjust_spec_key('spec/foo.rb', [])).to eq('spec/foo.rb')
    end

    it 'returns key unchanged when line part is empty' do
      expect(described_class.adjust_spec_key('spec/foo.rb:', [])).to eq('spec/foo.rb:')
    end

    it 'returns key unchanged when line part is non-numeric' do
      expect(described_class.adjust_spec_key('spec/foo.rb:abc', [])).to eq('spec/foo.rb:abc')
    end

    it 'returns key unchanged when line is zero' do
      expect(described_class.adjust_spec_key('spec/foo.rb:0', [])).to eq('spec/foo.rb:0')
    end
  end

  describe 'mixed add+delete hunk' do
    it 'collects deletion old_linenos and offsets lines past the hunk by net +1' do
      # Hunk replaces 2 old lines (10, 11) with 3 new lines => net +1
      lines = [
        mock_line(old_lineno: 10, origin: :deletion),
        mock_line(old_lineno: 11, origin: :deletion),
        mock_line(old_lineno: -1, origin: :addition),
        mock_line(old_lineno: -1, origin: :addition),
        mock_line(old_lineno: -1, origin: :addition),
      ]
      hunk = mock_hunk(old_start: 10, old_lines: 2, new_start: 10, new_lines: 3, lines: lines)

      expect(described_class.changed_old_lines([hunk])).to eq([10, 11])
      # Line 20 is past the hunk, should shift by +1
      expect(described_class.adjust_lines([20], [hunk])).to eq([21])
    end
  end

  describe 'unsorted hunks' do
    it 'produces cumulative offsets even when hunks are passed in reverse order' do
      hunk_early = mock_hunk(old_start: 10, old_lines: 0, new_start: 10, new_lines: 5)
      hunk_late  = mock_hunk(old_start: 30, old_lines: 0, new_start: 35, new_lines: 3)

      # Passing in reverse order
      result = described_class.adjust_lines([5, 20, 40], [hunk_late, hunk_early])

      expect(result).to include(5)   # before both hunks
      expect(result).to include(25)  # 20 + 5
      expect(result).to include(48)  # 40 + 5 + 3
    end
  end

  describe '.changed_old_lines' do
    it 'returns old line numbers that were deleted' do
      lines = [
        mock_line(old_lineno: 10, origin: :deletion),
        mock_line(old_lineno: -1, origin: :addition),
        mock_line(old_lineno: 11, origin: :deletion),
        mock_line(old_lineno: 12, origin: :context),
      ]
      hunk = mock_hunk(old_start: 10, old_lines: 3, new_start: 10, new_lines: 2, lines: lines)

      result = described_class.changed_old_lines([hunk])
      expect(result).to eq([10, 11])
    end

    it 'returns empty for context-only hunks' do
      lines = [mock_line(old_lineno: 10, origin: :context)]
      hunk = mock_hunk(old_start: 10, old_lines: 1, new_start: 10, new_lines: 1, lines: lines)

      expect(described_class.changed_old_lines([hunk])).to be_empty
    end
  end

  describe '.pure_insertion?' do
    it 'returns true when all lines are additions' do
      lines = [
        mock_line(old_lineno: -1, origin: :addition),
        mock_line(old_lineno: -1, origin: :addition),
      ]
      hunk = mock_hunk(old_start: 10, old_lines: 0, new_start: 10, new_lines: 2, lines: lines)

      expect(described_class.pure_insertion?([hunk])).to be true
    end

    it 'returns false when any line is a deletion' do
      lines = [
        mock_line(old_lineno: 10, origin: :deletion),
        mock_line(old_lineno: -1, origin: :addition),
      ]
      hunk = mock_hunk(old_start: 10, old_lines: 1, new_start: 10, new_lines: 1, lines: lines)

      expect(described_class.pure_insertion?([hunk])).to be false
    end

    it 'returns true for empty hunks array' do
      expect(described_class.pure_insertion?([])).to be true
    end
  end
end
