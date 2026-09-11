# frozen_string_literal: true

describe Testsort::RepositoryManager::ProjectSetup do
  let(:project) do
    instance_double(
      Testsort::Projects::Base,
      change_project_files: nil,
      setup_commands: ['cmd-a', 'cmd-b'],
    )
  end

  before do
    Testsort.configuration.project = project
    allow(Bundler).to receive(:with_original_env).and_yield
  end

  it 'invokes change_project_files with the working directory once' do
    allow_any_instance_of(described_class).to receive(:run)

    expect(project).to receive(:change_project_files).with(Testsort::Paths.root).once

    described_class.setup
  end

  it 'runs the commands returned by the project hook' do
    expect(project).to receive(:setup_commands).with(parallel: true).and_return(['only-this'])
    expect_any_instance_of(described_class).to receive(:run).with('only-this').once

    described_class.setup(parallel: true)
  end

  it 'runs each setup command in order' do
    received = []
    allow_any_instance_of(described_class).to receive(:run) { |_, cmd| received << cmd }

    described_class.setup

    expect(received).to eq(['cmd-a', 'cmd-b'])
  end
end
