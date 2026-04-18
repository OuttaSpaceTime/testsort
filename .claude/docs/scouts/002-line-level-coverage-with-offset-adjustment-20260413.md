# Scout: Line-Level Coverage with Diff-Offset Adjustment

**Status:** IN PROGRESS  
**Date:** 2026-04-13  
**Complexity:** Medium-Large

## Problem Frame

**Today:** Testsort stores a `spec_file × source_file` coverage matrix. When files change, all specs covering those files are prioritized. Granularity is file-level.

**After:** Testsort stores a `spec_example × source_file` matrix (rows are per-example, keyed by `spec_file:line`) plus per-(example, file) **line vectors** storing which source lines were hit. Offset adjustment via git diff hunks keeps stale coverage data usable across edits. Per-example rows enable line-targeted rspec output (`rspec spec/foo_spec.rb:42:67`).

## Resolved Design Decisions

### DG1: Two-layer storage (Approach B)
- **Layer 1:** `spec_example × source_file` matrix — coarse filter, existing strategy code unchanged
- **Layer 2:** Per-(example, file) line vectors — only consulted for nonzero matrix cells during prioritization

### DG2: Per-example matrix rows
- `spec_file_to_index` keys become `"spec/models/user_spec.rb:42"` (file + example line)
- `file_path(spec)` uses `spec.metadata[:line_number]` to preserve per-example granularity
- Enables line-targeted rspec arguments in command output

### DG3: Uniform offset adjustment — no extra storage
- Use current diff hunks at prioritization time to offset-adjust stored line numbers
- No content snapshots, no hashes, no diff storage needed
- Stored coverage is relative to whenever measured; current diff is relative to HEAD; offset bridges the gap
- Works regardless of how many dirty edits happened between runs

### DG4: Spec-side offset adjustment
- Offset applies uniformly to both source and spec line numbers
- Shifted `it` blocks → offset-adjusted, old coverage preserved
- Modified `it` blocks → run unconditionally (old coverage unreliable)
- New `it` blocks → run unconditionally (no stored coverage)
- Distinction comes from diff: context lines = shifted, added/removed within hunk = modified

### DG5: Pure insertions — file-level fallback
- When a file has only pure insertions (no modified lines), fall back to file-level prioritization for that file
- Avoids context-radius heuristic complexity; can be refined later

### DG6: Priority ordering (no mid-run re-ranking)
- Order: new/modified examples → line-matched examples → file-matched examples → everything else
- Fresh coverage stored for next run, not used mid-run
- One full bootstrapping run required; then incremental subset runs acceptable
- Uncovered failures only caught on next full run (CI, nightly, periodic `testsort prepare`)

### DG7: Line vector storage format
- JSON hash: key `"example_idx,file_idx"` → array of line numbers
- Consistent with existing serializer pattern (index mappings already JSON)
- Debuggable; performance revisited at scale if needed

## Scenario Handling

| Scenario | Action |
|---|---|
| New source file | No coverage data — invisible until next measurement |
| Deleted source file | All specs covering it prioritized (file-level, skip line vectors) |
| Pure insertion in source file | File-level fallback for that file |
| Lines modified in source file | Offset-adjust stored line vectors, intersect with changed lines |
| New `it` block in spec | Runs unconditionally (no stored coverage) |
| Modified `it` block | Runs unconditionally (old coverage unreliable) |
| Shifted `it` block | Offset-adjusted, old coverage preserved |
| Deleted `it` block | Removed from matrix on next measurement |
| Multiple dirty runs | Current diff hunks always used; no stored diff state needed |

## Affected Components

| Component | File | Impact |
|---|---|---|
| CoverageMeasurement | `coverage_measurement.rb` | Store line vectors per-example; rows keyed by `spec_file:line` |
| FileToIndexMapping | `file_to_index_mapping.rb` | Spec-side keys become `"file:line"` |
| CoverageMatrix | `coverage_matrix.rb` | More rows (examples vs files), columns unchanged |
| Serializer | `storage/serializer.rb` | New JSON file for line vectors |
| TestrunMerger | `storage/testrun_merger.rb` | Must merge line vectors alongside matrix |
| Changeset | `changeset.rb` | Expose diff hunks per file via Rugged diff API |
| New: DiffOffsetAdjuster | (new file) | Reads diff hunks, shifts stored line numbers; applied to source and spec sides |
| New: LineVectorStore | (new file) | Stores/retrieves per-(example, file) line vectors as JSON |
| Prioritization (base) | `prioritization.rb` | File-level filter → line vector intersection → reduced example list |
| Strategies | `strategies/*.rb` | **Unchanged** — receive a matrix slice, unaware of lines |
| `prioritized` command | `commands/prioritized.rb` | Output `spec:line` arguments; priority ordering logic |
| Configuration | `configuration.rb` | New granularity option (file-level vs line-level mode) |

## Open Decision Gates

None — all gates resolved during scout.

## Risks

### R1: `class_eval` blind spot (existing, document only)
`cli.rb` loads commands via `class_eval` — never appears in Coverage.result. Not new to this feature but worth documenting. Line-level coverage may create false expectation of completeness.

### R2: Shared examples trigger gap
Editing `spec/support/shared_examples.rb` won't trigger re-runs of examples that include it, because the changed file is spec support, not source code. **Mitigation:** treat `spec/support/` changes like spec changes. Coverage itself tracks the shared example file on the source side — use that to identify affected examples.

### R3: Matrix row growth (monitor, don't optimize)
Per-example rows: 30,000 examples × 500 files × 4 bytes = ~60MB. Up from ~400KB. Acceptable for now. Later: `Int16` halves it; sparse representation if profiling shows need.

### R4: Staged changes skew diff
`diff_workdir` misses staged changes. **Mitigation:** diff HEAD tree against working tree directly (`repo.diff(repo.head.target.tree, nil)`) to capture both staged and unstaged.

### R5: Incomplete bootstrapping run
If first full run is interrupted, matrix is partial. Unchanged examples that never ran have no coverage data. **Mitigation:** warn when matrix covers <80% of known examples.

### R6: (Withdrawn) Random order — not a risk, line numbers are file-stable regardless of execution order.

## Test Seams

- `CoverageMeasurement#cover` — assert line vectors collected per-example
- `LineVectorStore` — unit test storage/retrieval round-trip
- `DiffOffsetAdjuster` — deterministic pure function: stored lines + diff hunks → adjusted lines
- `Changeset` — test diff hunk extraction via Rugged
- `Prioritization` — test file-filter → line-intersection → reduced-example pipeline
- Integration: end-to-end test with a known matrix, a known diff, assert correct example ordering
