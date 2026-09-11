# frozen_string_literal: true

module Testsort
  class Configuration
    attr_reader :coverage_mode, :line_level,
                :line_level_filter_common, :line_level_strength_sort, :line_level_naive_order
    attr_accessor :project

    def initialize
      @oneshot_lines = true
      @lines = nil
      @line_level = false
      @line_level_filter_common = true
      @line_level_strength_sort = true
      @line_level_naive_order = false
      @project = Projects::Base.new
      compute_coverage_mode
    end

    def line_level=(use_line_level)
      @line_level = use_line_level
    end

    def line_level_filter_common=(value)
      @line_level_filter_common = value
    end

    def line_level_strength_sort=(value)
      @line_level_strength_sort = value
    end

    def line_level_naive_order=(value)
      @line_level_naive_order = value
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
