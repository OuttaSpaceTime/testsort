# frozen_string_literal: true

require_relative 'lib/testsort/version'

Gem::Specification.new do |spec|
  spec.name = 'testsort'
  spec.version = Testsort::VERSION
  spec.authors = ['Felix Eschey']
  spec.email = ['felix.eschey@makandra.de']

  spec.summary = 'Run tests for changed code first'
  spec.description = 'A CLI tool for coverage based test case prioritization.' 
  spec.homepage = 'https://github.com/OuttaSpaceTime/testsort'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata['allowed_push_host'] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'activesupport'
  spec.add_dependency 'json'
  spec.add_dependency 'makandra-rubocop'
  spec.add_dependency 'memoized'
  spec.add_dependency 'numo-gnuplot'
  spec.add_dependency 'numo-narray'
  spec.add_dependency 'open3'
  spec.add_dependency 'parallel_tests'
  spec.add_dependency 'rugged'
  spec.add_dependency 'thor'


  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
