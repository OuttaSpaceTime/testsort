desc 'compare', 'Run file-level and line-level prioritization against specific commits and report APFD'

option :parallel, aliases: '-p', type: :boolean, desc: 'Run evaluation in parallel', banner: '[bool]'
option :commits, aliases: '-c', type: :array, desc: 'Commit SHAs to evaluate (required, no auto history walk)', banner: 'SHA SHA SHA'
option :project, aliases: '-P', type: :string, desc: 'Project hook subclass name (e.g. "radfahrausbildung")', banner: '[name]'
option :fresh, aliases: '-f', type: :boolean, desc: 'Wipe the evaluation cache before running (forces every commit to be re-evaluated)', banner: '[bool]'
option :strategies, aliases: '-S', type: :array, desc: 'Prioritization strategies to compare (defaults: file_level line_level). Known: file_level, line_level, line_no_common, line_no_strength, line_naive, agent', banner: 'STRAT STRAT'
option :target_dir, aliases: '-t', type: :string, desc: 'Target project directory to evaluate against (default: cwd). Lets you invoke compare from the testsort gem dir while operating on a different project.', banner: '[path]'

def compare(*files)
  Dir.chdir(options.target_dir) if options.target_dir
  Evaluation::Compare.new.call(
    parallel: options.parallel || false,
    files: files,
    commits: options.commits || [],
    project: options.project,
    fresh: options.fresh || false,
    strategies: options.strategies,
  )
end
