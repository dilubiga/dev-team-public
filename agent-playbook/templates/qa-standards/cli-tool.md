# QA Standards — CLI Tool

Paste this section into your project's `CLAUDE.md` under `## QA Standards`.
The QA agent reads and enforces these standards for every task it verifies.

---

## QA Standards

### Help & Documentation
- `--help` (and `-h`) must work on every command and subcommand.
- Help text must be accurate — it must describe the current behavior, not a previous version.
- Verify: `python -m src.cli --help` exits with code `0` and produces non-empty output.
- All arguments and options must appear in help text with a description.

### Exit Codes
- `0` — success
- `1` — general error (invalid input, operation failed)
- `2` — usage error (wrong arguments, missing required flags) — argparse/click default
- Other non-zero codes must be documented in the README if used.
- Tests must assert the exit code for both success and failure paths.

### Error Messages
- Invalid or missing input must produce a **human-readable error message** on stderr.
- Error messages must NOT include Python stack traces when the error is a user mistake.
  (Stack traces are acceptable for unexpected internal errors in debug mode only.)
- Error messages must be actionable: tell the user what was wrong and what to do about it.
- Verify: supply invalid input, confirm stderr contains a useful message and exit code ≠ 0.

### Stdin / Stdout / Stderr
- Use **stdout** for primary output (data the user asked for).
- Use **stderr** for progress messages, warnings, and errors.
- Never mix errors and data on stdout — this breaks piping.
- Test piping: `python -m src.cli [args] | head` must not produce errors.

### File I/O
- **Missing input file**: must exit with a clear error message, not a `FileNotFoundError` stack trace.
- **Permission error**: must exit with a clear error, not crash.
- **Output file already exists**: document the behavior (overwrite / error / prompt) and test it.
- **Empty input file**: handle gracefully — document whether this is valid input.

### Idempotency
- Running the CLI command twice on the same input must produce the same result.
- If the command modifies state (e.g., writes to a file or DB), verify that re-running does not
  corrupt or duplicate data (unless the command is explicitly designed to append).
- Document any commands that are intentionally non-idempotent.

### Cross-Platform Paths
- Use `pathlib.Path` for all file path manipulation — never string concatenation.
- Do not hardcode `/` or `\` as directory separators.
- Test with paths that have spaces in them.
