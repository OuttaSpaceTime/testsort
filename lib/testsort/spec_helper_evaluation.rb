require 'testsort'

evaluation = Testsort::Evaluation::TestsuiteEvaluation.new
coverage_measurement = Testsort::CoverageMeasurement.new
coverage_measurement.start

RSpec.configure do |config|
  config.reporter.register_listener evaluation, :example_finished

  config.after do |example|
    coverage_measurement.cover(example)
  end

  config.after(:suite) do
    evaluation.evaluate_suite
    coverage_measurement.finish
  end
end
