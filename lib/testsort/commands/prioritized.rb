desc 'all', 'Run the prioritized testsuite'

option :parallel, aliases: '-p', type: :boolean, desc: 'Run evaluation in parallel', banner: '[bool]'
option :strategy, aliases: '-s', type: :string, desc: 'Specify the used prioritization strategy', banner: '[string]'
option :to_oneshot_lines, aliases: '-o', type: :boolean, desc: 'Convert coverage to one shot entries', banner: '[bool]'

def prioritized(files = [])
  # binstub_file = 'bin/rspec'
  # command = File.exist?(binstub_file) ? binstub_file : 'bundle exec rspec'
  command = options.parallel ? 'bundle exec parallel_rspec' : 'bundle exec rspec'

  if files.any? || (options.strategy.present? && options.strategy.casecmp('random') == 0)
    command << ' '
    command << files.join(' ')
  elsif Paths.last_run_stored?
    coverage_measurement = CoverageMeasurement.new(from_disk: true, oneshot_lines: true)

    if options.strategy.blank? || options.strategy.casecmp('absolute') == 0 || options.strategy.casecmp('oneshot') == 0
      prioritization = Prioritization::Strategies::Absolute.new(Changeset.new, coverage_measurement)
    elsif options.strategy.casecmp('additional pseudo') == 0 || options.strategy.casecmp('additional_pseudo') == 0
      prioritization = Prioritization::Strategies::AdditionalPseudo.new(Changeset.new, coverage_measurement)
    elsif options.strategy.casecmp('additional') == 0
      prioritization = Prioritization::Strategies::Additional.new(Changeset.new, coverage_measurement)
    end

    prioritized_specs = prioritization.prioritized_spec_order(in_groups: options.parallel)


    if prioritized_specs.blank?
      puts "\n There are no prioritized specs \n"
      return
    end

    if options.parallel && prioritized_specs[0].is_a?(Array)
      command << " -o  '--order default' "
      # command << ' -n 9 '
      command << ' --specify-groups '
      command << "'"
      prioritized_specs.each_with_index do |group, index|
        group = group.reject { |path| path.include?('shared_examples') }
        command << group.join(',')
        command << '|' unless index == prioritized_specs.length - 1
      end
      command << "'"
      command = command.gsub(/\.\//, '')
    else
      command << ' --order default' unless options.parallel
      command << (prioritized_specs.join(' ').prepend(' ') || '')
    end
  end

  Bundler.with_original_env do
    system(*command)
  end
end
