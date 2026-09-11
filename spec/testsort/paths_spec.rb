# frozen_string_literal: true

describe Testsort::Paths do
  describe '.spec_folder_paths' do
    it 'delegates to the configured project' do
      project = instance_double(Testsort::Projects::Base, spec_folder_paths: ['spec/foo', 'spec/bar'])
      Testsort.configuration.project = project

      expect(described_class.spec_folder_paths).to eq(['spec/foo', 'spec/bar'])
    end
  end
end
