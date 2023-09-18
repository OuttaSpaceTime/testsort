module Testsort
  module Evaluation
    class Metrics
      def initialize(faults)
        @faults = Numo::DFloat.cast(faults)
      end

      def percentage_of_faults_detected(at_step)
        total_faults(at_step) / total_faults
      end

      def average_percentage_of_fault_detection(evaluate_at = -1)
        faults_covered = faults_revealed_at_sum(evaluate_at) / (total_faults * total_specs)
        offset = 1 / (2 * total_specs)
        result = 1 - faults_covered + offset
        return 0 if result.nan?

        result
      end

      def plot_results
        return if total_specs.to_i < 10

        linear_steps = Numo::Int64.linspace(1, total_specs.to_i - 1, 10)
        pfd_at_step = Numo::DFloat.zeros(1)

        linear_steps.each do |step|
          pfd_at_step = pfd_at_step.append(percentage_of_faults_detected(step))
        end

        gp = Numo::Gnuplot.new
        gp.set title: "APFD: #{average_percentage_of_fault_detection}, #{total_faults.to_i} faults detected"
        gp.set ylabel: 'Percentage of faults detected'
        gp.set xlabel: 'Percentage  of testsuite executed'
        gp.set yrange: 0..1.1
        gp.plot Numo::DFloat.linspace(0, 1, 11), pfd_at_step, w: 'lines'

        gp
      end

      def total_specs
        @faults.shape[0].to_f || 0.0
      end

      def total_faults(until_index = -1)
        @faults[0..until_index].ne(0).where.shape[0].to_f
      end

      def faults_revealed_at_sum(until_index = -1)
        positions_of_non_zero_elements = @faults[0..until_index].ne(0).where + 1
        if positions_of_non_zero_elements.empty?
          0
        else
          positions_of_non_zero_elements.sum
        end
      end
    end
  end
end
