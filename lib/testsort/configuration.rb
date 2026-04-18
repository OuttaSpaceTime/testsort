module Testsort
  class Configuration
    attr_reader :coverage_mode, :line_level

    def initialize
      @oneshot_lines = true
      @lines = nil
      @line_level = false
      compute_coverage_mode
    end

    def line_level=(use_line_level)
      @line_level = use_line_level
    end

    def coverage_mode=(coverage_mode_hash)
      @coverage_mode = coverage_mode_hash
    end

    def lines=(use_lines)
      @lines = use_lines
      compute_coverage_mode
    end

    def oneshot_lines=(use_oneshot_lines)
      @oneshot_lines = use_oneshot_lines
      compute_coverage_mode
    end

    def lines
      @lines
    end

    def oneshot_lines
      @oneshot_lines
    end

    def eval_coverage_supported?
      Coverage.respond_to?(:supported?) && Coverage.supported?(:eval)
    end

    private

    def compute_coverage_mode
      @coverage_mode = {
        oneshot_lines: @oneshot_lines,
        lines: @lines,
        eval: eval_coverage_supported?,
        branches: false,
      }
    end
  end
end
