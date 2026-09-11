# Testsort

As my bachelor's thesis I programmed and evaluated a CLI tool written as a Ruby gem to prioritize test cases by coverage data of a Ruby on Rails project.

- This gem is an experimental stage. Currently this repository is only advised to be used for educational purposes.

## How it works

Testsort records which specs cover which lines of code, then diffs your working tree against
the last commit. Specs touching changed code are ranked first, so a failure caused by the
change surfaces early in the run instead of at the end.

## Installation

Add it to the target project's `Gemfile`:

```ruby
gem 'testsort', path: '/path/to/testsort'
```

Then require the coverage hook at the top of `spec/spec_helper.rb`, before anything else loads:

```ruby
require 'testsort/spec_helper_coverage'
```

Use `testsort/spec_helper_evaluation` instead when you also want fault data recorded — it is a
superset of the coverage hook and is what the evaluation commands need.

## Usage

```bash
bundle exec testsort prioritized          # run the suite, changed-code specs first
bundle exec testsort prioritized -p       # same, via parallel_rspec
bundle exec testsort prioritized -s random
```

Two further commands support the thesis evaluation rather than everyday use:

```bash
bundle exec testsort prepare -c SHA -r SHA   # check out a fault-carrying commit for measurement
bundle exec testsort evaluate                # run the evaluation over prepared commits
```

A first run has no coverage data and falls back to the normal order; the data is written as
you run.

## Branches

`main` is the thesis state. `wip/experiments-recovered` carries later, unfinished experiments
— an agent-driven strategy, APFD comparison tooling, and line-level prioritization. That branch
is work in progress and its integration specs force-check-out the repository they run in, so
don't run its suite against a checkout holding uncommitted work.

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rake
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
