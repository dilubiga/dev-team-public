---
applyTo: '**'
---

# Copilot Instructions (applies globally)

# Engineering Standards

When generating or refactoring code/tests, follow these rules without exception.

## Design (SOLID)

- **Single Responsibility**: each module/class/function has one clear reason to change.
- **Open/Closed**: extend behavior via composition/inheritance; avoid editing stable code.
- **Liskov Substitution**: subclasses must honor base-class contracts; no surprising pre/post-conditions.
- **Interface Segregation**: prefer small, focused protocols/ABCs over fat interfaces.
- **Dependency Inversion**: depend on abstractions; inject dependencies (constructor/params) instead of hard-coding.

## Language & Stack

- **Python-first** unless the project's `CLAUDE.md` specifies otherwise.
- **Frozen dataclasses** for data containers: `@dataclass(frozen=True)`.
- **Full type hints everywhere**: function signatures, return types, and variables where non-obvious (PEP 484 / PEP 561).
- Prefer `Protocol` / `ABC` for contracts.
- Keep functions small and pure where possible; avoid side effects in utils.

## Style & Quality

- Conform to **PEP 8** (names, spacing, imports, line length ~100).
- Follow **PEP 257** for docstrings (modules, classes, public functions) — use **Google style**.
- Imports: stdlib → third-party → local, separated by blank lines.
- Descriptive variable names; no single-letter variables except loop counters and established math notation
  (e.g., `S`, `K`, `T` in option pricing is fine).
- **No `print()` for logging** — use the `logging` module or return values.

## Toolchain: `.claude/env.sh` (REQUIRED)

Every project bootstrapped from the agent-playbook has a `.claude/env.sh` that resolves the Python toolchain uniformly across hosts (notably Git Bash on Windows, where `pytest` and `ruff` are often not on PATH but `py` is). **Any agent or skill that runs tests, linters, or `pip` must source it first:**

```bash
source .claude/env.sh
```

After sourcing, use these environment variables in every command — never the bare binary name:

| Variable  | Use for                           |
|-----------|-----------------------------------|
| `${PY}`   | Any direct Python invocation      |
| `${PYTEST}` | Running tests                   |
| `${RUFF}` | Lint checks and autofix           |
| `${BLACK}` | Formatting                       |
| `${ISORT}` | Import sorting                   |
| `${PIP}`  | Installing dependencies           |

Example:
```bash
${PYTEST} --tb=short -v
${RUFF} check .
${BLACK} --check .
```

The env file also exposes a `check_toolchain` function that returns non-zero if any of pytest/ruff/black/isort is not importable by `${PY}`. The `/execute` orchestrator calls this in pre-flight and hard-fails the pipeline if anything is missing — so if you are an agent being spawned by `/execute`, you can trust that the toolchain works.

**If `source .claude/env.sh` fails, or if a command like `${PYTEST} --version` fails inside your agent session, do not fall back to static review or manual verification. Emit a BLOCKED message and halt** — fixing the environment is on-call's job, not the SWE's or the QA tester's.

## Linting & Formatting

- Run `${RUFF} --fix`, `${BLACK}`, and `${ISORT}` before commits.
- Keep the codebase lint-clean at all times.

## Performance

- **Prefer [Polars](https://pola.rs/) over pandas** for all new data-wrangling code.
  - Use the lazy API (`pl.scan_*` / `.lazy()` + `.collect()`) to unlock query optimization.
  - Avoid per-row iteration; express logic through Polars expressions (`pl.col`, `pl.when`, `.over()`, etc.).
- **Pandas** is allowed only when a third-party library requires a `DataFrame`. Convert at the boundary:
  `polars_df.to_pandas()` / `pl.from_pandas(pandas_df)` — keep core logic in Polars.
- **NumPy RNG**: always use `np.random.default_rng()`. NEVER use legacy `np.random.seed()` or bare
  `np.random.*` random calls.
- Prefer NumPy vectorization where Polars expressions don't apply; avoid `.apply` unless strongly justified.
- Benchmark critical paths; avoid premature optimization, but keep scalability in mind.

## Testing Standards (pytest)

- **One behavior per test**; prefer one primary assertion per test.
- Use **Arrange – Act – Assert** with blank lines between sections.
- Name tests descriptively: `test_<unit>__<scenario>__<expected>`.
- Use `expected` and `actual` variable names where applicable.
- Prefer `@pytest.mark.parametrize` with `pytest.param(..., id="...")` for readable cases.
- Use `pytest.raises` for exception testing.
- Use fixtures for reusable setup logic.
- All floating-point comparisons via `pytest.approx()` or `np.testing.assert_allclose()` with explicit tolerances.

### Test Template

```python
def test_<unit>__<scenario>__<expected>():
    # Arrange
    ...
    expected = ...

    # Act
    actual = ...

    # Assert
    assert actual == expected
```

## Asking for Clarification

When a spec, task, or requirement is ambiguous:

1. **Stop immediately** — do not guess or proceed with an assumption.
2. Write your question(s) clearly and concisely in the task file (append under `## Agent Questions`) OR
   ask the user directly if in an interactive session.
3. Wait for an answer before continuing.

**It is always better to ask one focused question than to implement the wrong thing.**
