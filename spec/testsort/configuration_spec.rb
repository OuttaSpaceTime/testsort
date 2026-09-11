# frozen_string_literal: true

describe Testsort::Configuration do
  subject(:config) { described_class.new }

  describe '#coverage_mode' do
    it 'returns a hash with default values' do
      expect(config.coverage_mode).to be_a(Hash)
      expect(config.coverage_mode[:oneshot_lines]).to eq(true)
      expect(config.coverage_mode[:branches]).to eq(false)
    end
  end

  describe '#lines' do
    it 'defaults to nil' do
      expect(config.lines).to be_nil
    end

    it 'can be set' do
      config.lines = true
      expect(config.lines).to eq(true)
    end
  end

  describe '#oneshot_lines' do
    it 'defaults to true' do
      expect(config.oneshot_lines).to eq(true)
    end

    it 'can be set' do
      config.oneshot_lines = false
      expect(config.oneshot_lines).to eq(false)
    end
  end

  describe 'coverage_mode regeneration via setters' do
    it 'updates coverage_mode when lines= and oneshot_lines= are called' do
      config.lines = true
      config.oneshot_lines = false

      expect(config.coverage_mode[:lines]).to eq(true)
      expect(config.coverage_mode[:oneshot_lines]).to eq(false)
    end

    it 'reflects oneshot_lines=false in coverage_mode immediately' do
      config.oneshot_lines = false
      expect(config.coverage_mode[:oneshot_lines]).to eq(false)
    end
  end

  describe '#coverage_mode=' do
    it 'overrides the coverage mode hash' do
      custom = { lines: true, branches: true }
      config.coverage_mode = custom
      expect(config.coverage_mode).to eq(custom)
    end
  end

  describe '#eval_coverage_supported?' do
    it 'returns a boolean' do
      expect([true, false]).to include(config.eval_coverage_supported?)
    end
  end

  describe '#project' do
    it 'defaults to a Testsort::Projects::Base instance' do
      expect(config.project).to be_a(Testsort::Projects::Base)
    end

    it 'can be reassigned' do
      custom = Testsort::Projects::Base.new
      config.project = custom
      expect(config.project).to eq(custom)
    end
  end
end
