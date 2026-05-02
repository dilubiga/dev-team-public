# QA Standards — Web Application

Paste this section into your project's `CLAUDE.md` under `## QA Standards`.
The QA agent reads and enforces these standards for every task it verifies.

---

## QA Standards

### HTTP Responses
- All routes must return the appropriate HTTP status code:
  - `200 OK` for successful GET/PATCH
  - `201 Created` for successful POST that creates a resource
  - `204 No Content` for successful DELETE
  - `400 Bad Request` for invalid input
  - `401 Unauthorized` for missing/invalid auth
  - `403 Forbidden` for authenticated but unauthorized
  - `404 Not Found` for missing resources
  - `422 Unprocessable Entity` for validation errors (FastAPI default)
  - `500 Internal Server Error` only for unhandled exceptions (must not leak stack traces to client)
- Every route must have a test that verifies the status code for both the happy path and at least one error path.

### Input Validation
- All user-supplied input must be validated before use.
- Invalid input must produce a `400` or `422` response with a **human-readable error message** (not a raw stack trace).
- Test: submit deliberately invalid payloads and verify the response message is useful.

### Authentication & Authorization (if applicable)
- Protected routes must return `401` when called without credentials.
- Routes with role-based access must return `403` when called by a user with insufficient permissions.
- Tokens/sessions must not be logged in plain text.
- Tests must cover: no auth, wrong auth, insufficient role, correct auth.

### Security
- **No hardcoded secrets or API keys** anywhere in source code. Use environment variables.
  QA must `grep -r "password\|secret\|api_key\|token" src/` and verify no literals are found.
- CORS configuration must be explicit (not `*` in production settings).
- CSRF protection must be in place for state-changing endpoints (if using cookies/sessions).
- User-supplied data must not be interpolated into SQL queries — use parameterized queries or ORM.

### Templates & Rendering
- All templates must render without errors for the happy-path data.
- Verify that missing optional fields do not cause `KeyError` or `NoneType` exceptions in templates.
- Static assets (CSS, JS) must be referenced by their correct paths.

### Database Migrations (if applicable)
- Migrations must run cleanly on a **fresh (empty) database**.
- Verify: `alembic upgrade head` (or equivalent) on a clean DB completes without errors.
- Verify: `alembic downgrade -1` can reverse the latest migration without data loss.

### Environment Isolation
- Tests must not depend on a specific local state (e.g., must not require a pre-seeded production DB).
- Use a test database or in-memory database for all tests.
- Environment variables required by the app must be documented in `.env.example`.
