# frozen_string_literal: true

RSpec.shared_context 'with strategy fixtures', :strategy do
  let(:coverage_matrix) do
    Testsort::CoverageMeasurement::CoverageMatrix.new(
      Numo::Int32[[5, 3, 0],
                   [0, 2, 1],
                   [4, 0, 0],
                   [0, 0, 0]]
    )
  end

  let(:code_file_to_index) do
    Testsort::CoverageMeasurement::FileToIndexMapping.new(
      path_hash: { 'app/models/user.rb' => 0, 'app/models/post.rb' => 1, 'app/helpers/foo.rb' => 2 },
      index_hash: { 0 => 'app/models/user.rb', 1 => 'app/models/post.rb', 2 => 'app/helpers/foo.rb' }
    )
  end

  # Note: index_hash uses string keys to match JSON deserialization behavior.
  # Numo's `format` returns string indices, and fetch_specs does fetch_values on index_hash.
  let(:spec_file_to_index) do
    Testsort::CoverageMeasurement::FileToIndexMapping.new(
      path_hash: { 'spec/a_spec.rb' => 0, 'spec/b_spec.rb' => 1, 'spec/c_spec.rb' => 2, 'spec/d_spec.rb' => 3 },
      index_hash: { '0' => 'spec/a_spec.rb', '1' => 'spec/b_spec.rb', '2' => 'spec/c_spec.rb', '3' => 'spec/d_spec.rb' }
    )
  end

  let(:affected_files) { ['app/models/user.rb', 'app/models/post.rb'] }

  let(:changeset) do
    instance_double(Testsort::Changeset, affected: affected_files)
  end

  let(:measurement) do
    double('CoverageMeasurement',
           coverage_matrix: coverage_matrix,
           code_file_to_index: code_file_to_index,
           spec_file_to_index: spec_file_to_index)
  end

  let(:empty_changeset) do
    instance_double(Testsort::Changeset, affected: [])
  end
end
