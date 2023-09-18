# frozen_string_literal: true

module Testsort
  class Error < StandardError
    class CoverageNotStarted < Error; end
  end
end
