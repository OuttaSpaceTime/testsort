# frozen_string_literal: true

# AgentCLI is defined inside Testsort::CLI's class_eval context, so it lands
# at Testsort::CLI::AgentCLI. The final `subcommand` call registers it under
# the `agent` command name.

class AgentCLI < Thor
  class_option :no_pretty, type: :boolean, default: false

  desc 'universe', 'Show specs covering the current diff'
  def universe
    queries = Testsort::Agent::Queries.new
    specs = queries.universe
    output(specs: specs, count: specs.size, line_level: Testsort.configuration.line_level)
  rescue Testsort::Error => e
    error_output(e.message)
  end

  desc 'suggest [STRATEGY]', 'Get prioritized ordering from a strategy'
  option :parallel, type: :boolean, default: false
  option :format, type: :string, default: 'json', enum: %w[json lines]
  def suggest(strategy = 'absolute')
    queries = Testsort::Agent::Queries.new(strategy: strategy)
    result = queries.suggest(parallel: options[:parallel])
    if options[:format] == 'lines'
      flat = result.first.is_a?(Array) ? result.flatten : result
      flat.each { |s| puts s }
    else
      payload =
        if result.first.is_a?(Array)
          { groups: result, parallel: true, strategy: strategy }
        else
          { specs: result, parallel: false, strategy: strategy }
        end
      output(payload)
    end
  rescue Testsort::Error => e
    error_output(e.message)
  end

  desc 'run SPEC...', 'Run specs and record results'
  option :parallel, type: :boolean, default: false
  option :from_stdin, type: :boolean, default: false
  def run_specs(*specs)
    if specs.empty? && options[:from_stdin]
      specs = $stdin.read.split("\n").reject(&:empty?)
    end
    raise Testsort::Error, 'no specs provided' if specs.empty?

    result = Testsort::Agent::SpecRunner.run(specs: specs, parallel: options[:parallel])
    session = Testsort::Agent::Session.load
    session.append_run(specs: specs, results: result[:examples])
    output(
      ran_count:              result[:examples].size,
      exit_status:            result[:exit_status],
      examples:               result[:examples],
      degraded_to_file_level: result[:degraded_to_file_level],
    )
  rescue Testsort::Error => e
    error_output(e.message)
  end

  # Map the user-facing command name 'run' to the run_specs method.
  # (Thor's own #run method conflicts with the command name, so we use a
  # different method name and alias it here.)
  map 'run' => :run_specs

  desc 'run-floor', 'Run any unrun specs in Universe'
  option :parallel, type: :boolean, default: false
  def run_floor
    queries = Testsort::Agent::Queries.new
    universe = queries.universe
    session = Testsort::Agent::Session.load
    remaining = universe.reject { |k| session.executed_set.include?(k) }

    if remaining.empty?
      output(floor_satisfied: true, ran_count: 0, examples: {})
      return
    end

    result = Testsort::Agent::SpecRunner.run(specs: remaining, parallel: options[:parallel])
    session.append_run(specs: remaining, results: result[:examples])
    output(
      floor_satisfied:        true,
      ran_count:              result[:examples].size,
      examples:               result[:examples],
      degraded_to_file_level: result[:degraded_to_file_level],
    )
  rescue Testsort::Error => e
    error_output(e.message)
  end

  # Explicit map for hyphenated variant (Thor maps underscored methods to
  # underscored names, not hyphenated; the map call adds both).
  map 'run-floor' => :run_floor

  desc 'describe PATH...', 'Extract RSpec describe/context/it descriptions from spec files (one or more, accepts `spec/foo_spec.rb` or `./spec/foo_spec.rb:42`)'
  option :from_stdin, type: :boolean, default: false
  def describe_specs(*specs)
    if specs.empty? && options[:from_stdin]
      specs = $stdin.read.split("\n").reject(&:empty?)
    end
    raise Testsort::Error, 'no spec paths provided' if specs.empty?

    files = specs.map { |s| s.split(':', 2).first }.uniq
    output(Testsort::Agent::Describe.describe_files(files))
  rescue Testsort::Error => e
    error_output(e.message)
  end

  map 'describe' => :describe_specs

  no_commands do
    def output(hash)
      if options[:no_pretty]
        puts JSON.generate(hash)
      else
        puts JSON.pretty_generate(hash)
      end
    end

    def error_output(msg)
      $stderr.puts JSON.generate(error: msg)
      exit 1
    end
  end
end

desc 'agent SUBCOMMAND', 'Agent-facing CLI surface'
subcommand 'agent', AgentCLI
