# frozen_string_literal: true

describe Testsort::Projects::Base do
  subject(:project) { described_class.new }

  describe '#branch_name' do
    it 'raises NotImplementedError with the class name' do
      expect { project.branch_name }.to raise_error(NotImplementedError, /Testsort::Projects::Base#branch_name/)
    end
  end

  describe '#spec_folder_paths' do
    it 'raises NotImplementedError with the class name' do
      expect { project.spec_folder_paths }.to raise_error(NotImplementedError, /Testsort::Projects::Base#spec_folder_paths/)
    end
  end

  describe '#setup_commands' do
    it 'raises NotImplementedError with the class name' do
      expect { project.setup_commands }.to raise_error(NotImplementedError, /Testsort::Projects::Base#setup_commands/)
    end
  end

  describe '#ignored_file_types' do
    it 'returns an empty array' do
      expect(project.ignored_file_types).to eq([])
    end
  end

  describe '#change_project_files' do
    it 'returns nil and does not raise' do
      expect { project.change_project_files('/tmp') }.not_to raise_error
      expect(project.change_project_files('/tmp')).to be_nil
    end
  end
end
