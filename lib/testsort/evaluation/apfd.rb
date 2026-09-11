# frozen_string_literal: true

require 'csv'
require 'json'

module Testsort
  module Evaluation
    module Apfd
      module_function

      # Computes Average Percentage of Fault Detection (APFD).
      #
      # @param failures_narray [Numo::NArray] 1-D integer array, one element per spec.
      #   A non-zero value means a fault was first detected at that spec's position.
      # @param examples_count [Integer] total number of specs (n_specs)
      # @return [Float] APFD in the range 0..1, or Float::NAN when there are no faults.
      #
      # Formula (1-indexed positions): 1 - sum(T_i) / (n_faults * n_specs) + 1 / (2 * n_specs)
      # where T_i is the 1-indexed position of the spec that first reveals fault i.
      def average_percentage_of_fault_detection(failures_narray, examples_count)
        fault_positions = failures_narray.ne(0).where
        n_faults = fault_positions.shape[0].to_f

        return Float::NAN if n_faults.zero?

        # Convert 0-indexed positions to 1-indexed before summing
        sum_of_first_failures = (fault_positions + 1).sum.to_f
        offset = 1.0 / (2 * examples_count.to_f)

        1.0 - sum_of_first_failures / (n_faults * examples_count.to_f) + offset
      end

      # Arithmetic mean of an array of numbers.
      def mean(values)
        sum = 0.0
        values.each { |n| sum += n.to_f }
        sum / values.count.to_f
      end

      # Scans evaluation_data_dir for per-process env-N data files produced
      # by parallel_rspec runs and concatenates each (oid, kind, run_type)
      # group into the un-suffixed canonical file that
      # collect_apfd_per_run_type expects.
      #
      # File name pattern recognised:
      #   <oid>-(faults|failures|executed_specs|execution_times)-<run_type>-env-<N>
      #
      # For each group the env-N files are sorted numerically by N so that
      # positions are deterministic across runs. Values are joined with ","
      # (matching the Storage#write_evaluation_files format). After merging
      # the source env-N files are deleted.
      #
      # No-op when no env-N files exist (sequential / non-parallel runs).
      def merge_per_env_files!(evaluation_data_dir)
        kinds = %w[faults failures executed_specs execution_times]
        kind_pattern = kinds.join('|')
        # Matches: <oid>-<kind>-<run_type>-env-<N>
        # where run_type may itself contain underscores/hyphens
        env_file_re = /\A([0-9a-f]+)-(#{kind_pattern})-(.+)-env-(\d+)\z/

        groups = Hash.new { |h, k| h[k] = [] }

        Dir.glob(File.join(evaluation_data_dir, '*')).each do |path|
          base = File.basename(path)
          m = env_file_re.match(base)
          next unless m

          oid, kind, run_type, env_n = m[1], m[2], m[3], m[4].to_i
          groups[[oid, kind, run_type]] << [env_n, path]
        end

        return if groups.empty?

        groups.each do |(oid, kind, run_type), env_files|
          # Sort by env number ascending for deterministic ordering
          sorted_paths = env_files.sort_by { |n, _| n }.map { |_, p| p }

          merged_content = sorted_paths.map { |p| File.read(p).chomp }.join(',')

          target = File.join(evaluation_data_dir, "#{oid}-#{kind}-#{run_type}")
          # Preserve existing content (e.g. from a non-parallel process) if any
          if File.exist?(target)
            existing = File.read(target).chomp
            merged_content = [existing, merged_content].reject(&:empty?).join(',')
          end

          File.write(target, "#{merged_content}\n")

          sorted_paths.each { |p| FileUtils.rm_f(p) }
        end
      end

      # Reads per-commit failure data files and computes APFD per run_type.
      #
      # @param evaluation_data_dir [String] path to directory containing fault data files.
      #   Files are named like "<oid>-<run_type>-faults-…".
      # @param run_types [Array<String>] e.g. %w[random absolute additional additional_pseudo]
      # @param no_failure_commits [Array<String>] OIDs to skip.
      # @return [Hash{String => Array<Float>}] { run_type => [apfd, …] }
      def collect_apfd_per_run_type(evaluation_data_dir, run_types:, no_failure_commits:)
        result = run_types.index_with { [] }

        file_paths = Dir.glob(File.join(evaluation_data_dir, '**'))

        file_paths.each do |file_path|
          current_oid = file_path[%r{/(\w+)-}, 1]
          next if file_path.include?('no_faults')
          next if no_failure_commits.include?(current_oid)
          next unless file_path.include?('-faults-')

          faults_array = File.read(file_path).split(',').map(&:to_i)
          faults_narray = Numo::Int32.cast(faults_array)

          next if faults_narray.empty? || faults_narray.ne(0).where.empty?

          apfd = average_percentage_of_fault_detection(faults_narray, faults_narray.shape[0])

          matched_type = run_types.find { |rt| file_path.include?(rt) }
          next unless matched_type

          result[matched_type] << apfd
        end

        result
      end

      # Converts the APFD-per-run-type hash to a CSV string.
      # Header row contains run_type names; each subsequent row is one commit's values.
      #
      # @param apfd_per_run_type [Hash{String => Array<Float>}]
      # @return [String] CSV content
      def to_csv(apfd_per_run_type)
        run_types = apfd_per_run_type.keys
        columns   = apfd_per_run_type.values
        row_count = columns.map(&:size).max || 0

        CSV.generate do |csv|
          csv << run_types
          row_count.times do |i|
            csv << columns.map { |col| col[i] }
          end
        end
      end

      # Scatter plot of APFD values from a CSV file.
      #
      # @param data [Hash{String => Array<Float>}] apfd_per_run_type
      # @param output [String] output file path (e.g. "scatter.jpg")
      def scatter_plot(data, output:)
        require 'numo/gnuplot'

        run_types = data.keys
        font_size = 20

        run_types.each_with_index do |run_type, column_index|
          # Write a temp CSV for gnuplot; column 1 = index, column 2 = apfd
          tmp_csv = Tempfile.new(['apfd_scatter', '.csv'])
          begin
            data[run_type].each_with_index { |v, i| tmp_csv.puts "#{i},#{v}" }
            tmp_csv.flush

            file_out = output.sub(/(\.\w+)$/, "_#{run_type}\\1")

            Numo.gnuplot do
              set :zeroaxis
              set xlabel: 'Number of evaluated testsuite', font: "Times New Roman, #{font_size}"
              set ylabel: 'APFD', font: "Times New Roman, #{font_size}"
              set datafile: "separator ','"
              set xtics: { font: "Times New Roman, #{font_size - 2}" }
              set ytics: { font: "Times New Roman, #{font_size - 2}" }
              plot ["'#{tmp_csv.path}'", u: '1:2', t: '']
              self.output file_out
            end
          ensure
            tmp_csv.close
            tmp_csv.unlink
          end
        end
      end

      # Histogram plot of APFD values.
      #
      # @param data [Hash{String => Array<Float>}] apfd_per_run_type
      # @param output [String] output file path (e.g. "hist.jpg")
      def histogram_plot(data, output:)
        require 'numo/gnuplot'

        run_types = data.keys
        font_size = 20

        run_types.each do |run_type|
          tmp_csv = Tempfile.new(['apfd_hist', '.csv'])
          begin
            data[run_type].each_with_index { |v, i| tmp_csv.puts "#{i},#{v}" }
            tmp_csv.flush

            file_out = output.sub(/(\.\w+)$/, "_#{run_type}\\1")

            Numo.gnuplot do
              run 'n=20'
              run 'max=1.'
              run 'min=0.'
              run 'width=(max-min)/n'
              run 'hist(x,width)=width*floor(x/width)+width/2.0'
              set datafile: "separator ','"
              set xlabel: 'APFD', font: "Times New Roman, #{font_size}"
              set ylabel: 'Cumulated APFD values', font: "Times New Roman, #{font_size}"
              set 'boxwidth width*0.91'
              set 'style fill solid 0.5'
              set xtics: { font: "Times New Roman, #{font_size - 2}" }
              set ytics: { font: "Times New Roman, #{font_size - 2}" }
              plot "'#{tmp_csv.path}'", u: '(hist($2,width)):(1.0)',
                                        s: true,
                                        f: true,
                                        w: 'boxes',
                                        lc: "rgb'green'",
                                        notitle: true
              self.output file_out
            end
          ensure
            tmp_csv.close
            tmp_csv.unlink
          end
        end
      end
    end
  end
end
