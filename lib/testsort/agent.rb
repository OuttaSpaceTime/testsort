# frozen_string_literal: true

module Testsort
  module Agent
    autoload :Queries,         'testsort/agent/queries'
    autoload :Session,         'testsort/agent/session'
    autoload :ResultListener,  'testsort/agent/result_listener'
    autoload :ResultCollector, 'testsort/agent/result_collector'
    autoload :SpecRunner,      'testsort/agent/spec_runner'
    autoload :Describe,        'testsort/agent/describe'
  end
end
