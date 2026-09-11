# frozen_string_literal: true

# Integration-level verification of ProjectEvaluation#evaluate's record_run call sequence.
#
# Full end-to-end integration (spawning a subprocess per strategy per commit) is verified
# in Phase D via a 4-commit evaluation run on a real fixture project. This spec only checks
# that the 'agent' strategy is part of the record_run call list, alongside 'absolute' and
# 'oneshot', without exercising the subprocess machinery.

describe Testsort::Evaluation::ProjectEvaluation do
  describe '.evaluate' do
    it "calls record_run with 'agent' strategy alongside 'absolute' and 'oneshot'" do
      # Spy on the private record_run method to capture which run_types are requested.
      run_types_recorded = []

      allow(described_class).to receive(:record_run).and_wrap_original do |original, run_type, **kwargs|
        run_types_recorded << run_type
        # Do NOT delegate to the original — avoid any git/filesystem operations.
      end

      # Stub RepositoryIterator to yield a single fake commit pair and stop.
      fake_iterator = double('RepositoryIterator')
      allow(fake_iterator).to receive(:each_pair_with_index).and_yield('abc123', 'def456', 0)
      allow(Testsort::RepositoryManager::RepositoryIterator).to receive(:new).and_return(fake_iterator)

      # Stub Paths helpers to prevent filesystem reads during set_instance_variables.
      allow(Testsort::Paths).to receive(:run_number).and_return('1')

      # Stub the faults-file check so we don't skip the body.
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with(Testsort::Paths.faults_file_path(run_type: 'random', oid: 'abc123', use_data_folder: true))
        .and_return(false)

      described_class.evaluate([])

      expect(run_types_recorded).to include('absolute', 'oneshot', 'agent')
      expect(run_types_recorded.index('agent')).to be > run_types_recorded.index('oneshot'),
        "expected 'agent' to be recorded after 'oneshot', got order: #{run_types_recorded.inspect}"
    end
  end
end
