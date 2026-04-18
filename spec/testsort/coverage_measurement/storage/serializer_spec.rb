# frozen_string_literal: true

describe Testsort::CoverageMeasurement::Storage::Serializer, :git do
  let(:original_line_level) { Testsort.configuration.line_level }

  before do
    @original_dir = Dir.getwd
    Dir.chdir(@tmp_repo_path)
  end

  after do
    Dir.chdir(@original_dir) if @original_dir
    Testsort.configuration.line_level = original_line_level
  end

  def build_and_serialize(line_level: false)
    Testsort.configuration.line_level = line_level
    m = Testsort::CoverageMeasurement.new
    m.instance_variable_set(:@spec_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'spec/a_spec.rb' => 0 },
        index_hash: { 0 => 'spec/a_spec.rb' }
      ))
    m.instance_variable_set(:@code_file_to_index,
      Testsort::CoverageMeasurement::FileToIndexMapping.new(
        path_hash: { 'app/a.rb' => 0 },
        index_hash: { 0 => 'app/a.rb' }
      ))
    cm = Testsort::CoverageMeasurement::CoverageMatrix.new(Numo::Int32[[3]])
    cm.record(0, 0, hit_count: 3, lines: [1, 2, 3]) if line_level
    m.instance_variable_set(:@coverage_matrix, cm)
    commit_file('seed.txt', 'seed') # create an initial commit so HEAD resolves
    m.serialize
    m
  end

  describe 'meta.json' do
    it 'writes meta.json on serialize with schema_version, line_level, and measured_at_sha' do
      build_and_serialize(line_level: true)

      meta_path = File.join(@tmp_repo_path, Testsort::Paths::META)
      expect(File.exist?(meta_path)).to be(true)

      meta = JSON.parse(File.read(meta_path))
      expect(meta['schema_version']).to eq(Testsort::CoverageMeasurement::Storage::Serializer::SCHEMA_VERSION)
      expect(meta['line_level']).to eq(true)
      expect(meta['measured_at_sha']).to match(/\A[0-9a-f]{40}\z/)
    end

    it 'aborts with CoverageStoreIncompatible on schema_version mismatch' do
      build_and_serialize(line_level: false)
      meta_path = File.join(@tmp_repo_path, Testsort::Paths::META)
      data = JSON.parse(File.read(meta_path))
      data['schema_version'] = 999
      File.write(meta_path, JSON.pretty_generate(data))

      expect {
        Testsort::CoverageMeasurement.new(from_disk: true)
      }.to raise_error(Testsort::Error::CoverageStoreIncompatible, /re-run.*prepare/i)
    end

    it 'aborts with CoverageStoreIncompatible on line_level mismatch' do
      build_and_serialize(line_level: false)
      Testsort.configuration.line_level = true

      expect {
        Testsort::CoverageMeasurement.new(from_disk: true)
      }.to raise_error(Testsort::Error::CoverageStoreIncompatible, /re-run.*prepare/i)
    end

    it 'warns on SHA mismatch but continues loading' do
      build_and_serialize(line_level: false)
      # New commit → HEAD sha changes
      commit_file('other.txt', 'other')

      expect($stderr).to receive(:puts).with(/sha|sha mismatch|HEAD/i).at_least(:once)

      loaded = Testsort::CoverageMeasurement.new(from_disk: true)
      expect(loaded.coverage_matrix[0, 0]).to eq(3)
    end

    it 'aborts when meta.json is absent but other store files exist (legacy)' do
      build_and_serialize(line_level: false)
      File.delete(File.join(@tmp_repo_path, Testsort::Paths::META))

      expect {
        Testsort::CoverageMeasurement.new(from_disk: true)
      }.to raise_error(Testsort::Error::CoverageStoreIncompatible, /re-run.*prepare/i)
    end
  end
end
