# QA Standards — Data Pipeline / ETL

Paste this section into your project's `CLAUDE.md` under `## QA Standards`.
The QA agent reads and enforces these standards for every task it verifies.

---

## QA Standards

### Schema Validation
- The output of every pipeline stage must conform to a **documented schema**.
- Schema must specify: column names, Polars dtypes, nullable/non-nullable, and value constraints.
- Tests must assert the schema explicitly:
  ```python
  assert result.schema == expected_schema
  ```
- Verify that adding an unexpected column to the input does not silently corrupt the output.

### Row Count & Data Loss
- Every pipeline stage must have a test that verifies **no silent data loss**.
- For transformations: `len(output) == expected` for known inputs.
- For filters: verify the filtered-out rows match the filter condition exactly.
- For joins: verify row counts before and after, and document the join type (inner/left/outer).
- If data loss is intentional (deduplication, filtering), it must be logged and testable.

### Null Handling
- Every column that can contain nulls must have **explicit null-handling logic** — not implicit drops.
- Tests must include rows with nulls in every nullable column and verify the output is correct.
- Using `.drop_nulls()` without justification is a FAIL. Document why dropping nulls is correct.
- Polars expressions that silently propagate nulls (most do) must be verified to do so intentionally.

### Idempotency
- Running the full pipeline twice on the same input must produce **identical output**.
- If the pipeline writes to storage (file, database, object store), re-running must not:
  - Duplicate rows
  - Create duplicate files
  - Corrupt the existing output
- Test: run the pipeline, run it again, compare outputs with `assert_frame_equal`.

### Error Handling & Bad Records
- Bad records (wrong type, missing required field, out-of-range value) must be:
  - **Logged** with enough context to identify the source record, AND
  - **Quarantined** (written to a separate bad-records file/table) OR
  - **Rejected** with a clear error message — never silently swallowed.
- Tests must include deliberately malformed records and verify the bad-record path.

### Polars-Specific Standards
- Use **explicit dtypes** in all schema definitions. No implicit casting.
  ```python
  # Good
  pl.read_csv("data.csv", schema={"price": pl.Float64, "date": pl.Date})
  # Bad
  pl.read_csv("data.csv")  # inferred dtypes can change with different data
  ```
- Use the **lazy API** (`pl.scan_*` / `.lazy()` + `.collect()`) for pipelines on large data.
- Never use `.to_pandas()` inside a pipeline — only at final output boundaries if required by a
  downstream library.
- `.apply()` / `.map_elements()` must have a comment justifying why a Polars expression is insufficient.

### Determinism
- Any pipeline stage that involves random sampling or shuffling must use `np.random.default_rng(seed)`
  with an explicit seed for tests.
- Production pipelines that are intentionally non-deterministic must document this.

### Performance (document expectations in CLAUDE.md)
- Define expected throughput for the project (e.g., "process 1M rows in < 30 seconds on a laptop").
- Add a `@pytest.mark.slow` performance test that verifies this bound on a realistic dataset size.
