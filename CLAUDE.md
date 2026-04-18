# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Testsort is a Ruby gem (CLI tool) for coverage-based test case prioritization in Ruby on Rails projects. It was built as a bachelor's thesis. It analyzes code coverage data to reorder test execution so that tests covering changed code run first.

## Commands

- **Install dependencies:** `bundle install`
- **Run all tests:** `bundle exec rspec`
- **Run a single test:** `bundle exec rspec spec/path/to/file_spec.rb`
- **Run default rake task (tests):** `bundle exec rake`

## Architecture

The gem is a Thor CLI (`exe/testsort`) with three commands: `prepare`, `prioritized`, and `evaluate`.

**Core pipeline:**

1. **Changeset** (`lib/testsort/changeset.rb`) — Uses Rugged (libgit2) to detect modified/new/deleted files from git status.
2. **CoverageMeasurement** (`lib/testsort/coverage_measurement/`) — Stores and manages a coverage matrix (Numo::NArray) mapping specs to source files. `FileToIndexMapping` maps file paths to matrix indices. `CoverageMatrix` wraps the numeric array with slicing/querying operations.
3. **Prioritization** (`lib/testsort/prioritization/`) — Three strategies (all subclasses working through the base `Prioritization` class):
   - **Absolute** — Ranks specs by total coverage of changed files.
   - **Additional** — Greedy algorithm selecting the spec with the highest marginal coverage at each step.
   - **AdditionalPseudo** — Variant of Additional.
4. **Evaluation** (`lib/testsort/evaluation/`) — Iterates over repository history to evaluate prioritization effectiveness. Uses `RepositoryManager` to check out commits and `Metrics` to compute results.
5. **RepositoryManager** (`lib/testsort/repository_manager/`) — Manages git operations: checking out commits, resetting state, iterating history for evaluation runs.

**Key dependencies:** Thor (CLI), Rugged (git), Numo::NArray (matrix operations), parallel_tests (parallel execution), numo-gnuplot (plotting evaluation results).

## Configuration

Global config in `lib/testsort.rb` via `Testsort.configure`. Two settings: `lines` (line-level coverage) and `oneshot_lines` (binary coverage — covered or not).
