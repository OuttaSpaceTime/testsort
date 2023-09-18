# frozen_string_literal: true

require 'active_support/all'
require 'byebug'
require 'numo/narray'
require 'numo/gnuplot'
require 'rugged'
require 'json'
require 'thor'
require 'open3'
require 'memoized'
require 'parallel_tests'

require_relative 'testsort/version'
require_relative 'testsort/error'
require_relative 'testsort/paths'
require_relative 'testsort/changeset'
require_relative 'testsort/cli'
require_relative 'testsort/io_helper'
require_relative 'testsort/configuration'
require_relative 'testsort/repository_manager/repository'
require_relative 'testsort/repository_manager/file_reset'
require_relative 'testsort/repository_manager/file_manager'
require_relative 'testsort/repository_manager/project_setup'
require_relative 'testsort/repository_manager/repository_iterator'
require_relative 'testsort/repository_manager/repository_preparation'
require_relative 'testsort/evaluation/testsuite_evaluation'
require_relative 'testsort/evaluation/exception_tracker'
require_relative 'testsort/evaluation/project_evaluation'
require_relative 'testsort/evaluation/metrics'
require_relative 'testsort/coverage_measurement/coverage_measurement'
require_relative 'testsort/coverage_measurement/file_to_index_mapping'
require_relative 'testsort/coverage_measurement/coverage_matrix'
require_relative 'testsort/coverage_measurement/storage/testrun_merger'
require_relative 'testsort/prioritization/prioritization'
require_relative 'testsort/prioritization/spec'
require_relative 'testsort/prioritization/spec_list'
require_relative 'testsort/prioritization/strategies/absolute'
require_relative 'testsort/prioritization/strategies/additional_pseudo'
require_relative 'testsort/prioritization/strategies/additional'

module Testsort
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end

Testsort.configure do |config|
  config.lines = false
  config.oneshot_lines = true
end
