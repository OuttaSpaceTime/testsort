# frozen_string_literal: true

describe Testsort::CoverageMeasurement do
  describe '#process_coverage_result line-vector capture' do
    let(:measurement) { described_class.new }

    before do
      measurement.spec_file_to_index.insert('spec/models/user_spec.rb:1')
      measurement.coverage_matrix.new_row(0, 0)

      allow(Testsort::Paths).to receive(:relative_path_of).and_return('app/models/user.rb')
      allow(Testsort::Paths).to receive(:project_root_path_regex).and_return(/.*/)
      allow(::Coverage).to receive(:result).and_return(
        '/abs/app/models/user.rb' => { oneshot_lines: [3, 5, 9] }
      )
    end

    it 'records line vectors even when line_level is false (regression: cached data must survive a later line_level toggle)' do
      Testsort.configuration.line_level = false

      measurement.send(:process_coverage_result)

      spec_idx = measurement.spec_file_to_index['spec/models/user_spec.rb:1']
      file_idx = measurement.code_file_to_index['app/models/user.rb']
      expect(measurement.coverage_matrix.lines_for(spec_idx, file_idx)).to eq([3, 5, 9])
    end
  end
end
