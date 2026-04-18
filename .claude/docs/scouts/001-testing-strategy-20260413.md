# Scout: Testing Strategy for Testsort

## Problem Frame
Zero test coverage beyond a version smoke test. Need basic happy-path integration tests for CLI commands and unit tests for all core logic.

## Decisions
- **Git fixtures:** Real temp repos via `Rugged::Repository.init_at` (not stubs)
- **Integration scope for `prioritized`:** Stub `system` call, test command string construction
- **Test doubles for CoverageMeasurement:** OpenStruct/double responding to `coverage_matrix`, `code_file_to_index`, `spec_file_to_index`
- **File organization:** Mirror `lib/` structure
- **Framework:** RSpec (already configured)

## Testability Layers
1. **Pure logic:** Spec, SpecList, CoverageMatrix, FileToIndexMapping, Configuration
2. **Internal collaborators:** Absolute, Additional, AdditionalPseudo strategies
3. **Git-dependent:** Changeset, RepositoryManager::*
4. **Ruby Coverage API:** CoverageMeasurement (integration only)

## Risks
- `Paths.root` coupling — must stub in all git-context specs
- Numo::NArray version sensitivity — pin inputs to expected outputs
- Changeset temp repo setup — test each status type separately

## Scope
- **Now:** Shared :git context, unit tests for layers 1-2, integration for `prioritized` + `prepare`
- **Later:** `evaluate` integration, serializer/merger, Metrics
- **Out:** Full e2e running rspec on fixture projects
