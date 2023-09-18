module Testsort
  class Configuration
    attr_reader :coverage_mode

    def initialize
      @coverage_mode = { oneshot_lines: @oneshot_lines || true, lines: @lines, eval: eval_coverage_supported?, branches: false }
    end

    def coverage_mode=(coverage_mode_hash)
      @coverage_mode = coverage_mode_hash
    end

    def lines=(use_lines)
      @lines = use_lines
    end

    def oneshot_lines=(use_oneshot_lines)
      @oneshot_lines = use_oneshot_lines
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
  end
end
