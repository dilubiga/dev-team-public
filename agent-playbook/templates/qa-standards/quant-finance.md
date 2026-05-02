# QA Standards — Quantitative Finance

Paste this section into your project's `CLAUDE.md` under `## QA Standards`.
The QA agent reads and enforces these standards for every task it verifies.

---

## QA Standards

### Numerical Precision
- All floating-point comparisons MUST use `pytest.approx()` or `np.testing.assert_allclose()` with
  **explicit absolute or relative tolerances**. No bare `==` comparisons on floats.
- Document the tolerance and its justification in the test (e.g., `# 1bp tolerance for Black-Scholes`).

### Reference Values
- Every pricing function MUST be tested against at least one **known analytical solution** or
  **published benchmark value** (textbook, academic paper, or Bloomberg reference).
- The test must cite the source (comment with author/year/page or formula name).
- Example: Black-Scholes at-the-money call with S=K=100, T=1, r=0.05, σ=0.2 = 10.4506 (Hull, 10th ed.)

### Boundary Conditions
Every pricing function must include tests for:
- **At-the-money** (S ≈ K): verify price is reasonable, Greeks are near their ATM limits
- **Deep in-the-money** (S >> K for calls): price approaches intrinsic value
- **Deep out-of-the-money** (S << K for calls): price approaches zero
- **Zero volatility** (σ → 0): price equals discounted intrinsic value
- **Zero time-to-expiry** (T → 0): price equals intrinsic value (max(S-K, 0) for call)
- **Very long expiry** (T → ∞): price bounded by underlying price (call ≤ S)

### Arbitrage Constraints
Verify these mathematical relationships hold:
- **Non-negative prices**: `price >= 0` for all inputs
- **Put-call parity**: `C - P = S * exp(-q*T) - K * exp(-r*T)` (within numerical tolerance)
- **Monotonicity in strike**: call price decreases as K increases; put price increases as K increases
- **Monotonicity in maturity**: for European options, longer maturity ≥ shorter maturity price (usually)
- **Upper/lower bounds**: call price ≤ spot; put price ≤ strike * exp(-r*T)

### Greeks Validation
If Greeks (delta, gamma, vega, theta, rho) are implemented:
- Verify each Greek against a **finite-difference bump** with step size h:
  - Delta: `(price(S+h) - price(S-h)) / (2h)` where h ≈ 0.01 * S
  - Vega: `(price(σ+h) - price(σ-h)) / (2h)` where h ≈ 0.001
- Tolerance for FD check: relative tolerance ≤ 1e-4 (or document if larger is justified)
- Verify sign conventions: call delta ∈ (0, 1), put delta ∈ (-1, 0), gamma > 0, vega > 0

### Monte Carlo Reproducibility
- Any Monte Carlo test MUST use `np.random.default_rng(seed)` with an explicit integer seed.
- The test must be deterministic: running it twice must produce exactly the same result.
- Never use `np.random.seed()` (legacy) or bare `np.random.*` calls.
- For convergence tests: run with N=10_000 paths minimum; document expected variance.

### Performance
- Pricing functions on standard scalar inputs must complete in **< 1 second per call**.
- If a function is expected to be slow (e.g., Monte Carlo with 100k paths), document the expected
  runtime in a comment and mark the test with `@pytest.mark.slow`.
- Vectorized functions (pricing a strip of options) must complete in < 5 seconds for N=1000.

### Data Types
- Use `float` for prices, rates, and vol. Never use `int` for financial quantities that can be fractional.
- Use `np.float64` explicitly when precision matters.
- Polars columns for financial time series: use `pl.Float64`, never `pl.Float32` for pricing data.
