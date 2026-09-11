# Minimal RSpec bootstrap for direct `agent run`/`agent run-floor` invocations.
# Loaded via --require <full-path> from the SpecRunner subprocess.
#
# IMPORTANT: Do NOT load this file in `evaluate`/`compare` runs — it's only
# for direct `agent run`/`agent run-floor` invocations. Those other pipeline
# modes use their own listener stack (TestsuiteEvaluation via
# spec_helper_evaluation.rb). Running both listeners simultaneously would
# produce conflicting results files.

require 'testsort'

listener = Testsort::Agent::ResultListener.new

RSpec.configure do |c|
  c.reporter.register_listener listener, :example_finished
  c.after(:suite) { listener.flush }
end
