# frozen_string_literal: true

describe Testsort::Prioritization::Spec do
  subject(:spec) { described_class.new('spec/models/user_spec.rb') }

  it 'stores the path' do
    expect(spec.path).to eq('spec/models/user_spec.rb')
  end

  it 'defaults times_covered to 0' do
    expect(spec.times_covered).to eq(0)
  end

  it 'allows times_covered to be set' do
    spec.times_covered = 42
    expect(spec.times_covered).to eq(42)
  end
end
