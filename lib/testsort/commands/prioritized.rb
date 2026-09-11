desc 'all', 'Run the prioritized testsuite'

option :parallel, aliases: '-p', type: :boolean, desc: 'Run evaluation in parallel', banner: '[bool]'
option :strategy, aliases: '-s', type: :string, desc: 'Specify the used prioritization strategy', banner: '[string]'
option :to_oneshot_lines, aliases: '-o', type: :boolean, desc: 'Convert coverage to one shot entries', banner: '[bool]'

def prioritized(files = [])
  command = options.parallel ? 'bundle exec parallel_rspec' : 'bundle exec rspec'

  if files.any? || (options.strategy.present? && options.strategy.casecmp('random') == 0)
    command << ' '
    command << files.join(' ')
  elsif Paths.last_run_stored?
    coverage_measurement = CoverageMeasurement.new(from_disk: true, oneshot_lines: true)
    changeset = Changeset.new

    if options.strategy.blank? || options.strategy.casecmp('absolute') == 0 || options.strategy.casecmp('oneshot') == 0
      prioritization = Prioritization::Strategies::Absolute.new(changeset, coverage_measurement)
    elsif options.strategy.casecmp('additional pseudo') == 0 || options.strategy.casecmp('additional_pseudo') == 0
      prioritization = Prioritization::Strategies::AdditionalPseudo.new(changeset, coverage_measurement)
    elsif options.strategy.casecmp('additional') == 0
      prioritization = Prioritization::Strategies::Additional.new(changeset, coverage_measurement)
    end

    prioritized_specs = prioritization.prioritized_spec_order(in_groups: options.parallel)

    if prioritized_specs.blank?
      puts "\n There are no prioritized specs \n"
      return
    end

    # Filter to in-project specs only. Coverage capture sometimes records
    # absolute paths to gem-installed support specs (e.g.
    # `/.../some-gem/.../rubocop_spec.rb`). Passing those to
    # parallel_rspec breaks `sort_by_filesize` because the file:line key
    # gets stat'd literally with the line number appended. Drop anything
    # that doesn't look like a relative `spec/...` or `./spec/...` path.
    in_project = ->(key) { key.start_with?('spec/', './spec/') }
    prioritized_specs = prioritized_specs[0].is_a?(Array) ?
      prioritized_specs.map { |g| g.select(&in_project) }.reject(&:empty?) :
      prioritized_specs.select(&in_project)

    # parallel_tests' sort_by_filesize stats each "test" as a file path and
    # raises on `path.rb:42`. Strip `:line` from keys before passing to
    # parallel_rspec (this also kicks in when config.line_level=false but the
    # cached coverage was captured with line_level=true so spec_list still
    # holds example keys). Line-level priority degrades to spec-file priority
    # under parallel, but the run completes.
    strip_line = ->(arr) { arr.map { |k| k.split(':').first }.uniq }

    if options.parallel && prioritized_specs[0].is_a?(Array)
      # parallel_rspec auto-discovers spec files in spec/. If our groups
      # don't cover every discovered file, parallel_tests errors with
      # "other specs found in folders not specified in --specify-groups".
      # Append any uncovered spec files to the last group so coverage is
      # complete; their relative ordering doesn't matter to APFD because
      # they weren't in the priority list (they had no relevant coverage).
      prioritized_specs = prioritized_specs.map { |g| g.reject { |path| path.include?('shared_examples') } }
      prioritized_specs = prioritized_specs.map { |g| strip_line.call(g) }
      covered_set = prioritized_specs.flatten.to_set
      auto_discovered = Dir.glob('spec/**/*_spec.rb').reject { |p| p.include?('shared_examples') }
      missing = auto_discovered.reject { |p| covered_set.include?(p) || covered_set.include?("./#{p}") }
      prioritized_specs.last.concat(missing) if missing.any?

      command << " -o  '--order defined' "
      command << " -n #{prioritized_specs.size} "
      command << ' --specify-groups '
      command << "'"
      prioritized_specs.each_with_index do |group, index|
        command << group.join(',')
        command << '|' unless index == prioritized_specs.length - 1
      end
      command << "'"
      command = command.gsub(/\.\//, '')
    else
      prioritized_specs = strip_line.call(prioritized_specs) if options.parallel
      command << ' --order defined' unless options.parallel
      command << (prioritized_specs.join(' ').prepend(' ') || '')
    end
  end

  Bundler.with_unbundled_env do
    stdout, stderr, status = Open3.capture3(command)
    $stdout.print stdout
    $stderr.print stderr
    status.success?
  end
end

