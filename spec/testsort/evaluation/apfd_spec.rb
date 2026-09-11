# frozen_string_literal: true

# Load only the minimal dependencies needed for this module (not the full gem,
# which may reference files not yet present during incremental refactor work).
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'numo/narray'
require 'csv'
require 'fileutils'
require 'tmpdir'
require 'testsort/evaluation/apfd'

describe Testsort::Evaluation::Apfd do
  describe '.average_percentage_of_fault_detection' do
    # Helper to build a 1-D Int32 NArray from a plain Ruby array.
    def narray(*values)
      Numo::Int32.cast(values)
    end

    context 'when all faults are caught by the very first spec' do
      # 5 specs; spec 0 (1-indexed: 1) reveals all 3 faults, rest are 0.
      # sum_of_first_failures = 1 * 3 = 3
      # faults_covered = 3 / (3 * 5) = 0.2
      # offset = 1 / (2*5) = 0.1
      # APFD = 1 - 0.2 + 0.1 = 0.9  (= 1 - 1/(2n) for n=5)
      it 'returns a value close to 1 (specifically 1 - 1/(2n))' do
        failures = narray(3, 0, 0, 0, 0)
        apfd = described_class.average_percentage_of_fault_detection(failures, 5)
        expect(apfd).to be_within(1e-10).of(0.9)
      end
    end

    context 'when there are no faults (all zeros)' do
      it 'returns NaN' do
        failures = narray(0, 0, 0, 0, 0)
        result = described_class.average_percentage_of_fault_detection(failures, 5)
        expect(result).to be_nan
      end
    end

    context 'hand-computed example: 5 specs, 2 faults at 0-indexed positions 1 and 3' do
      # The source formula uses 1-indexed positions:
      #   T_A = 2 (0-indexed 1 → 1-indexed 2)
      #   T_B = 4 (0-indexed 3 → 1-indexed 4)
      # sum_of_first_failures = 2 + 4 = 6
      # faults_covered = 6 / (2 * 5) = 0.6
      # offset = 1 / (2*5) = 0.1
      # APFD = 1 - 0.6 + 0.1 = 0.5
      #
      # Note: the task brief stated 0.7, but that was derived from 0-indexed positions
      # (1+3)/(2*5). The source script adds +1 before summing (converting to 1-indexed),
      # so the correct result matching the source semantics is 0.5.
      it 'returns 0.5' do
        # spec 0 => no fault, spec 1 => fault A, spec 2 => no fault, spec 3 => fault B, spec 4 => no fault
        failures = narray(0, 1, 0, 1, 0)
        apfd = described_class.average_percentage_of_fault_detection(failures, 5)
        expect(apfd).to be_within(1e-10).of(0.5)
      end
    end

    context 'when faults are all caught by the last spec' do
      # 5 specs; spec 4 (1-indexed: 5) reveals 2 faults.
      # sum_of_first_failures = 5 * 2 = 10
      # faults_covered = 10 / (2 * 5) = 1.0
      # offset = 0.1
      # APFD = 1 - 1.0 + 0.1 = 0.1
      it 'returns a value close to 0' do
        failures = narray(0, 0, 0, 0, 2)
        apfd = described_class.average_percentage_of_fault_detection(failures, 5)
        expect(apfd).to be_within(1e-10).of(0.1)
      end
    end
  end

  describe '.mean' do
    it 'returns the arithmetic mean of an array' do
      expect(described_class.mean([1, 2, 3, 4, 5])).to eq(3.0)
    end

    it 'works with a single element' do
      expect(described_class.mean([7])).to eq(7.0)
    end

    it 'works with floats' do
      expect(described_class.mean([0.5, 1.5])).to be_within(1e-10).of(1.0)
    end

    it 'returns NaN for an empty array' do
      expect(described_class.mean([])).to be_nan
    end
  end

  describe '.merge_per_env_files!' do
    around do |example|
      Dir.mktmpdir('apfd_merge_spec') do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end

    def write_env_file(dir, name, content)
      path = File.join(dir, name)
      File.write(path, content)
      path
    end

    it 'concatenates env-N files for the same (oid, kind, run_type) into an un-suffixed file' do
      write_env_file(@tmpdir, 'abc123-faults-absolute-env-1', "0,1,0\n")
      write_env_file(@tmpdir, 'abc123-faults-absolute-env-2', "0,0,1\n")

      described_class.merge_per_env_files!(@tmpdir)

      merged = File.read(File.join(@tmpdir, 'abc123-faults-absolute'))
      expect(merged.chomp).to eq('0,1,0,0,0,1')
    end

    it 'sorts env-N files numerically so env-10 comes after env-2' do
      write_env_file(@tmpdir, 'def456-failures-line_level-env-2',  "0,1\n")
      write_env_file(@tmpdir, 'def456-failures-line_level-env-10', "1,0\n")

      described_class.merge_per_env_files!(@tmpdir)

      merged = File.read(File.join(@tmpdir, 'def456-failures-line_level'))
      # env-2 content must come before env-10 content
      expect(merged.chomp).to eq('0,1,1,0')
    end

    it 'does not mix data across different run_types' do
      write_env_file(@tmpdir, 'abc123-faults-absolute-env-1',   "1,0\n")
      write_env_file(@tmpdir, 'abc123-faults-line_level-env-1', "0,1\n")

      described_class.merge_per_env_files!(@tmpdir)

      absolute_file   = File.join(@tmpdir, 'abc123-faults-absolute')
      line_level_file = File.join(@tmpdir, 'abc123-faults-line_level')

      expect(File.read(absolute_file).chomp).to eq('1,0')
      expect(File.read(line_level_file).chomp).to eq('0,1')
    end

    it 'is a no-op when no env-N files exist' do
      write_env_file(@tmpdir, 'abc123-faults-absolute', "1,0,1\n")

      expect { described_class.merge_per_env_files!(@tmpdir) }.not_to raise_error

      # Existing unsuffixed file must be untouched
      expect(File.read(File.join(@tmpdir, 'abc123-faults-absolute')).chomp).to eq('1,0,1')
    end

    it 'deletes source env-N files after merging' do
      src1 = write_env_file(@tmpdir, 'abc123-faults-absolute-env-1', "0,1,0\n")
      src2 = write_env_file(@tmpdir, 'abc123-faults-absolute-env-2', "1,0,0\n")

      described_class.merge_per_env_files!(@tmpdir)

      expect(File.exist?(src1)).to be false
      expect(File.exist?(src2)).to be false
    end

    it 'preserves existing unsuffixed file content when merging env-N files' do
      write_env_file(@tmpdir, 'abc123-faults-absolute', "1,0\n")
      write_env_file(@tmpdir, 'abc123-faults-absolute-env-2', "0,1\n")

      described_class.merge_per_env_files!(@tmpdir)

      merged = File.read(File.join(@tmpdir, 'abc123-faults-absolute'))
      expect(merged.chomp).to eq('1,0,0,1')
    end
  end

  describe '.to_csv' do
    let(:apfd_per_run_type) do
      {
        'random'   => [0.8, 0.6, 0.9],
        'absolute' => [0.7, 0.5, 0.85],
        'additional' => [0.75, 0.55, 0.88]
      }
    end

    subject(:csv_string) { described_class.to_csv(apfd_per_run_type) }

    it 'includes a header row with run_type names' do
      header = CSV.parse(csv_string).first
      expect(header).to eq(%w[random absolute additional])
    end

    it 'produces one data row per commit' do
      rows = CSV.parse(csv_string)
      data_rows = rows.drop(1) # skip header
      expect(data_rows.size).to eq(3)
    end

    it 'places correct values in the first data row' do
      rows = CSV.parse(csv_string)
      first_data_row = rows[1].map(&:to_f)
      expect(first_data_row).to eq([0.8, 0.7, 0.75])
    end

    context 'when columns have different lengths' do
      let(:apfd_per_run_type) do
        { 'a' => [0.5, 0.6], 'b' => [0.7] }
      end

      it 'uses the longest column to determine row count' do
        rows = CSV.parse(csv_string)
        data_rows = rows.drop(1)
        expect(data_rows.size).to eq(2)
      end
    end
  end
end
