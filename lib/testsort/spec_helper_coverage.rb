require 'testsort'

coverage_measurement = Testsort::CoverageMeasurement.new
coverage_measurement.start

RSpec.configure do |config|
  config.after do |example|
    coverage_measurement.cover(example)
  end

  config.after(:suite) do
    coverage_measurement.finish
  end
end
