# frozen_string_literal: true

require 'json'

module Testsort
  module Evaluation
    # Multi-strategy APFD comparison summary.
    # Reads the per-commit per-strategy fault data produced by Compare and
    # emits a per-strategy ranking, per-commit details and noise-filter stats.
    module CompareSummary
      module_function

      def render(evaluation_dir:, coverage_dir:, commits:, strategies:, descriptions: {}, io: $stdout)
        per_commit_per_strategy = {}
        commits.each do |sha|
          per_commit_per_strategy[sha] = {}
          strategies.each do |strategy|
            per_commit_per_strategy[sha][strategy] = read_strategy_data(evaluation_dir, sha, strategy)
          end
        end

        emit_header(io)

        emit_per_strategy_summary(io, per_commit_per_strategy, strategies, commits)
        emit_per_commit_table(io, per_commit_per_strategy, strategies, commits, descriptions)
        emit_noise_summary(io, coverage_dir, commits)
        emit_per_commit_details(io, per_commit_per_strategy, strategies, commits, descriptions)
        emit_per_commit_winner(io, per_commit_per_strategy, strategies, commits)
        emit_first_fault_position(io, per_commit_per_strategy, strategies, commits)
      end

      def read_strategy_data(eval_dir, sha, strategy)
        faults_file = File.join(eval_dir, "#{sha}-faults-#{strategy}")
        specs_file  = File.join(eval_dir, "#{sha}-executed_specs-#{strategy}")
        return nil unless File.exist?(faults_file) && File.exist?(specs_file)

        faults = File.read(faults_file).strip.split(',')
        specs  = File.read(specs_file).strip.split(',')
        positions = faults.each_with_index.filter_map { |v, i| i + 1 if v == '1' }
        n_specs = faults.size
        n_faults = positions.size
        apfd =
          if n_faults.zero? || n_specs.zero?
            Float::NAN
          else
            (1.0 - positions.sum / (n_faults * n_specs.to_f)) + (1.0 / (2 * n_specs))
          end
        {
          n_specs:   n_specs,
          n_faults:  n_faults,
          apfd:      apfd,
          first_pos: positions.first,
          positions: positions,
          fault_specs: positions.map { |p| [p, specs[p - 1]] },
        }
      end

      def emit_header(io)
        io.puts '=' * 78
        io.puts 'MULTI-STRATEGY APFD COMPARISON  (parent-baseline noise filter active)'
        io.puts '=' * 78
      end

      def emit_per_strategy_summary(io, data, strategies, commits)
        io.puts "\n## Strategy ranking (mean APFD across commits with usable data)"
        io.printf "  %-22s %8s %8s %8s\n", 'strategy', 'n', 'mean', 'median'
        io.puts '-' * 60
        rows = strategies.map do |s|
          values = commits.map { |sha| data[sha][s] }.compact.map { |d| d[:apfd] }.reject(&:nan?)
          [s, values]
        end.sort_by { |_s, v| -(mean(v).nan? ? -1 : mean(v)) }
        rows.each do |strategy, values|
          io.printf "  %-22s %8d %8s %8s\n",
                    strategy,
                    values.size,
                    fmt(mean(values)),
                    fmt(median(values))
        end
      end

      def emit_per_commit_table(io, data, strategies, commits, descriptions)
        io.puts "\n## Per-commit APFD"
        header = format("  %-12s %-44s %s", 'commit', 'description', strategies.map { |s| s[0, 16].ljust(16) }.join(' '))
        io.puts header
        io.puts '-' * header.size
        commits.each do |sha|
          desc = (descriptions[sha] || '')[0, 44]
          cols = strategies.map do |s|
            d = data[sha][s]
            d ? fmt(d[:apfd]) : 'CRASH'
          end.map { |v| v.ljust(16) }
          io.printf "  %-12s %-44s %s\n", sha[0, 8], desc, cols.join(' ')
        end
      end

      def emit_noise_summary(io, coverage_dir, commits)
        io.puts "\n## Noise filter inputs (parent-commit failure pairs)"
        io.printf "  %-12s %22s %26s\n", 'commit', 'distinct exceptions', '(exception, line) pairs'
        io.puts '-' * 64
        commits.each do |sha|
          path = File.join(coverage_dir, sha, 'noise.json')
          if File.exist?(path)
            d = JSON.parse(File.read(path))
            io.printf "  %-12s %22d %26d\n", sha[0, 8], d.size, d.values.map(&:size).sum
          else
            io.printf "  %-12s %22s %26s\n", sha[0, 8], '-', '-'
          end
        end
      end

      def emit_per_commit_details(io, data, strategies, commits, descriptions)
        io.puts "\n## Real fault positions per commit (after noise filter)"
        commits.each do |sha|
          io.puts "\n  #{sha[0, 8]} — #{descriptions[sha] || ''}"
          strategies.each do |s|
            d = data[sha][s]
            if d.nil?
              io.printf "    %-22s CRASH\n", s
              next
            end
            tag = format('n=%d APFD=%s first=%s', d[:n_faults], fmt(d[:apfd]), d[:first_pos] || '-')
            io.printf "    %-22s %s\n", s, tag
          end
        end
      end

      def emit_per_commit_winner(io, data, strategies, commits)
        io.puts "\n## Winner per commit (best strategy by APFD)"
        commits.each do |sha|
          ranked = strategies.map { |s| [s, data[sha][s]&.dig(:apfd)] }
                              .reject { |_s, v| v.nil? || v.respond_to?(:nan?) && v.nan? }
                              .sort_by { |_s, v| -v }
          if ranked.empty?
            io.printf "  %-12s no usable data\n", sha[0, 8]
            next
          end
          best, best_apfd = ranked.first
          gap = ranked.size > 1 ? best_apfd - ranked[1][1] : 0
          io.printf "  %-12s %-22s APFD=%s (Δ next=%s)\n",
                    sha[0, 8], best, fmt(best_apfd), fmt(gap)
        end
      end

      def emit_first_fault_position(io, data, strategies, commits)
        io.puts "\n## First-fault position per (commit, strategy) — lower is better"
        header = format("  %-12s %s", 'commit', strategies.map { |s| s[0, 16].rjust(16) }.join(' '))
        io.puts header
        io.puts '-' * header.size
        commits.each do |sha|
          cols = strategies.map do |s|
            d = data[sha][s]
            (d&.dig(:first_pos) || '-').to_s.rjust(16)
          end
          io.printf "  %-12s %s\n", sha[0, 8], cols.join(' ')
        end
      end

      def fmt(value)
        return 'NaN'   if value.respond_to?(:nan?) && value.nan?
        return value.to_s unless value.is_a?(Numeric)
        format('%.4f', value)
      end

      def mean(values)
        values = values.reject(&:nan?)
        return Float::NAN if values.empty?
        values.sum / values.size.to_f
      end

      def median(values)
        values = values.reject(&:nan?).sort
        return Float::NAN if values.empty?
        mid = values.size / 2
        values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0
      end
    end
  end
end
