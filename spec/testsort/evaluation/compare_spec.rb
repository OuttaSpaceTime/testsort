# frozen_string_literal: true

describe Testsort::Evaluation::Compare do
  let(:io) { StringIO.new }
  subject(:compare) { described_class.new(io: io) }

  describe '#call (stubbed)' do
    before do
      allow(compare).to receive(:preflight!)
      allow(compare).to receive(:capture_noise)
      allow(compare).to receive(:capture_baseline)
      allow(compare).to receive(:prepare_for_strategy_passes)
      allow(compare).to receive(:run_strategy_pass)
      allow(Testsort::Evaluation::Apfd).to receive(:collect_apfd_per_run_type).and_return(
        'file_level' => [0.5, 0.6],
        'line_level' => [0.7, 0.8],
      )
      allow(compare).to receive(:safe_no_failure_commits).and_return([])
      allow(compare).to receive(:write_commit_keyed_csv)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
      allow(Testsort::Paths).to receive(:current_evaluation_data_folder).and_return('/tmp/forced')
    end

    it 'iterates each commit and runs every strategy on it' do
      expect(compare).to receive(:run_strategy_pass).with('abc', strategy: 'file_level', parallel: true, files: ['x.rb']).ordered
      expect(compare).to receive(:run_strategy_pass).with('abc', strategy: 'line_level', parallel: true, files: ['x.rb']).ordered

      compare.call(commits: ['abc'], parallel: true, files: ['x.rb'])
    end

    it 'runs each strategy once per commit when multiple commits' do
      seen = []
      allow(compare).to receive(:run_strategy_pass) { |_sha, strategy:, **_| seen << strategy }

      compare.call(commits: %w[abc def])

      expect(seen).to eq(%w[file_level line_level file_level line_level])
    end

    it 'honours --strategies override' do
      seen = []
      allow(compare).to receive(:run_strategy_pass) { |_sha, strategy:, **_| seen << strategy }

      compare.call(commits: ['abc'], strategies: %w[file_level line_naive])

      expect(seen).to eq(%w[file_level line_naive])
    end

    it 'rejects an unknown strategy' do
      expect { compare.call(commits: ['abc'], strategies: ['file_level', 'made_up']) }
        .to raise_error(described_class::PreflightError, /made_up/)
    end

    it 'prints per-strategy APFD summary' do
      compare.call(commits: ['abc'])
      expect(io.string).to include('file_level: n=2 mean=0.55')
      expect(io.string).to include('line_level: n=2 mean=0.75')
    end

    it 'writes a CSV to the evaluation folder' do
      expect(File).to receive(:write).with('/tmp/forced/compare_apfd.csv', kind_of(String))
      compare.call(commits: ['abc'])
    end
  end

  describe 'project resolution' do
    before do
      allow(compare).to receive(:preflight!)
      allow(compare).to receive(:capture_noise)
      allow(compare).to receive(:capture_baseline)
      allow(compare).to receive(:prepare_for_strategy_passes)
      allow(compare).to receive(:run_strategy_pass)
      allow(compare).to receive(:report_results)
    end

    it 'instantiates the named project subclass' do
      compare.call(commits: ['abc'], project: 'dummy')
      expect(Testsort.configuration.project).to be_a(Testsort::Projects::Dummy)
    end

    it 'leaves the configured project untouched when no name is given' do
      Testsort.configuration.project = Testsort::Projects::Radfahrausbildung.new
      compare.call(commits: ['abc'])
      expect(Testsort.configuration.project).to be_a(Testsort::Projects::Radfahrausbildung)
    end
  end

  describe '#preflight!' do
    let(:tmp_repo) { Dir.mktmpdir('compare-preflight') }

    around do |example|
      original_dir = Dir.getwd
      Dir.chdir(tmp_repo)
      Rugged::Repository.init_at(tmp_repo)
      File.write(File.join(tmp_repo, 'README'), 'x')
      example.run
    ensure
      Dir.chdir(original_dir)
      FileUtils.remove_entry(tmp_repo) if File.directory?(tmp_repo)
    end

    it 'rejects an empty commit list' do
      expect { compare.send(:preflight!, []) }.to raise_error(described_class::PreflightError, /No commits supplied/)
    end

    it 'rejects when cwd is not a git repository' do
      Dir.chdir(Dir.tmpdir)
      expect { compare.send(:preflight!, ['abc']) }.to raise_error(described_class::PreflightError, /Not a git repository/)
    end

    it 'rejects RAILS_ENV=production' do
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'production'))
      expect { compare.send(:preflight!, ['abc']) }.to raise_error(described_class::PreflightError, /production/)
    end
  end
end
