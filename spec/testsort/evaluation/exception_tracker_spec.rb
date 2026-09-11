# frozen_string_literal: true

require 'tmpdir'
require 'json'
require 'fileutils'
require 'testsort/evaluation/exception_tracker'

describe Testsort::Evaluation::ExceptionTracker do
  describe '.merge_files' do
    around do |example|
      Dir.mktmpdir('exception_tracker_spec') do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end

    def write_tracker_file(path, hash)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate(hash))
    end

    def read_tracker_file(path)
      JSON.parse(File.read(path))
    end

    it 'merges two source files into a single target file' do
      target = File.join(@tmpdir, 'noise.json')
      src1   = File.join(@tmpdir, 'noise.json.env-2')
      src2   = File.join(@tmpdir, 'noise.json.env-3')

      write_tracker_file(src1, 'RuntimeError: boom' => ['spec/a_spec.rb:10'])
      write_tracker_file(src2, 'ArgumentError: nope' => ['spec/b_spec.rb:20'])

      described_class.merge_files(target, src1, src2)

      result = read_tracker_file(target)
      expect(result['RuntimeError: boom']).to include('spec/a_spec.rb:10')
      expect(result['ArgumentError: nope']).to include('spec/b_spec.rb:20')
    end

    it 'preserves existing target content when merging source files into it' do
      target = File.join(@tmpdir, 'noise.json')
      src2   = File.join(@tmpdir, 'noise.json.env-2')

      # Process 1 wrote to the unsuffixed target; process 2 wrote to env-2
      write_tracker_file(target, 'RuntimeError: boom' => ['spec/a_spec.rb:10'])
      write_tracker_file(src2,   'NoMethodError: oops' => ['spec/c_spec.rb:5'])

      described_class.merge_files(target, src2)

      result = read_tracker_file(target)
      expect(result['RuntimeError: boom']).to include('spec/a_spec.rb:10')
      expect(result['NoMethodError: oops']).to include('spec/c_spec.rb:5')
    end

    it 'is idempotent when source paths do not exist' do
      target = File.join(@tmpdir, 'noise.json')
      write_tracker_file(target, 'RuntimeError: boom' => ['spec/a_spec.rb:10'])

      missing_src = File.join(@tmpdir, 'noise.json.env-99')

      # Should not raise or corrupt the target
      described_class.merge_files(target, missing_src)

      result = read_tracker_file(target)
      expect(result['RuntimeError: boom']).to include('spec/a_spec.rb:10')
    end

    it 'deletes source env-N files after merging' do
      target = File.join(@tmpdir, 'noise.json')
      src2   = File.join(@tmpdir, 'noise.json.env-2')
      src3   = File.join(@tmpdir, 'noise.json.env-3')

      write_tracker_file(src2, 'RuntimeError: boom' => ['spec/a_spec.rb:10'])
      write_tracker_file(src3, 'ArgumentError: nope' => ['spec/b_spec.rb:20'])

      described_class.merge_files(target, src2, src3)

      expect(File.exist?(src2)).to be false
      expect(File.exist?(src3)).to be false
    end

    it 'does not raise when called with no source paths and no existing target' do
      target = File.join(@tmpdir, 'noise.json')
      expect { described_class.merge_files(target) }.not_to raise_error
    end

    it 'deduplicates identical (exception, location) pairs across sources' do
      target = File.join(@tmpdir, 'noise.json')
      src2   = File.join(@tmpdir, 'noise.json.env-2')
      src3   = File.join(@tmpdir, 'noise.json.env-3')

      same_pair = { 'RuntimeError: boom' => ['spec/a_spec.rb:10'] }
      write_tracker_file(src2, same_pair)
      write_tracker_file(src3, same_pair)

      described_class.merge_files(target, src2, src3)

      result = read_tracker_file(target)
      expect(result['RuntimeError: boom'].size).to eq(1)
    end
  end
end
