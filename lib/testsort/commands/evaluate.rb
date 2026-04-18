desc 'all', 'Prepare the repository in a fault-full commit by checking out a previous commit and putting it into the staging area'

option :delete_previous_run_data, aliases: '-d', type: :boolean, desc: 'Delete folder form previous run', banner: '[bool]'
option :parallel, aliases: '-p', type: :boolean, desc: 'Run evaluation in parallel', banner: '[bool]'
option :plot, aliases: '-pl', type: :boolean, desc: 'Plots the results', banner: '[bool]'
option :clear_data, aliases: '-c', type: :string, desc: 'Clear data of the run type', banner: '[string]'

def evaluate(*files)
  if options.delete_previous_run_data
    RepositoryManager::FileManager.delete_data_from_previous_run
  end

  if options.clear_data.present?
    RepositoryManager::FileManager.clear_data_including(options.clear_data)
  end

  Evaluation::ProjectEvaluation.evaluate(files, parallel: options.parallel)
end
