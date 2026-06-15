# Coverage Reference — design techniques + risk-construct checklist

Heavy reference for `test-coverage-design`. Two parts: **(A)** how to design the fewest tests for the
widest coverage, **(B)** what risky constructs to scan code for and the oracle-independent test that
catches each. Part B's final section is **C/C++ only**.

## A. Test-design techniques (fewest cases, widest coverage)

| Technique | Use it to | One-liner |
|---|---|---|
| **Equivalence partitioning (EP)** | collapse an input domain | group inputs that should behave the same; test one representative per class |
| **Boundary-value analysis (BVA)** | find off-by-one / limit bugs | test at, just below, just above each boundary (incl. 0, empty, max, the overflow threshold) |
| **Decision tables** | combinations of conditions | enumerate condition→action rules; one case per rule |
| **State-transition** | stateful behaviour | cover legal transitions + a few illegal ones (full / empty, init / teardown) |
| **Pairwise / combinatorial** | many parameters | cover all *pairs* of values, not all combinations — most interaction bugs need only a pair |
| **Property-based** | "for all inputs, P holds" | assert an invariant over generated inputs (e.g. round-trip `parse(format(x)) == x`) |
| **Metamorphic** | no cheap oracle | assert a *relation* between runs (below) — needs no known-correct answer |
| **Differential** | a reference exists | run the unit + a trivially-correct / independent impl on the same input; compare |

**Minimal-set recipe:** partition (EP) → add boundaries (BVA) → tame multi-param explosion (pairwise) →
prioritise by risk. Stop when every obligation has one exercising case.

## Oracle-independent testing (the reliability core)

When you can't cheaply know the *right* answer (checksums, encoders, solvers, numeric kernels) — and
when the test author may share the implementer's blind spot — don't assert a hand-computed value. Assert
a **relation** instead:

- **Metamorphic** — re-derive the result a second way that *should* agree: compute in a wider type and
  compare (catches overflow without knowing the sum); reorder / concatenate inputs and assert the
  defined invariant; scale inputs and assert the defined effect.
- **Differential** — compare against a slow, obviously-correct reference implementation.
- **Property / invariant** — round-trip equality, monotonicity, idempotence, conservation.

These hold (or break) regardless of whether anyone "thought of" the specific bug — which is exactly why
they survive correlated LLM blind spots.

## B. Risk-construct checklist (scan code against every class)

Generic — each row: the construct → the failure it hides → the test that catches it.

| Construct | Failure it hides | Test that catches it |
|---|---|---|
| **Fixed-width accumulator / counter** (sum, hash, running total in `int`/`int32`) | overflow / wraparound on large or many inputs | metamorphic: same computation in a wider type, compare; BVA at the overflow threshold |
| **Index / modulo / ring arithmetic** (`% n`, `head`/`tail`, slicing) | off-by-one, wrap past capacity, out-of-bounds | BVA at 0 / 1 / capacity-1 / capacity / capacity+1; fill→drain→refill cycle |
| **Raw owning pointer / manual resource** (owns `new`/`malloc`/fd/lock, no RAII) | leak, double-free, use-after-free on copy / move / throw | exercise copy + move + self-assign + early-return / throw paths |
| **Unchecked input / parse** (`from_chars`, `atoi`, split, decode) | trailing garbage / partial input silently accepted | malformed, empty, partial, oversized tokens; assert reject + count |
| **Shared mutable state across threads** | data race, torn read, lost update | concurrent producer / consumer under stress; many iterations |
| **Empty / boundary / error paths** (0 items, max size, alloc / IO failure) | crash or wrong result on the unhappy path | explicit empty, single, max, and failure-injection cases |
| **Floating point / narrowing casts** (`double`→`int`) | precision loss, range overflow, NaN / Inf | boundary + out-of-range inputs; relation vs. a wider type |

Keep this list **living**: when a new confident-wrong class surfaces (as T2's overflow did), add a row +
its oracle-independent test.

## B — C/C++ only: sanitizer-class risks

For C/C++, the runtime-UB arm of this checklist is `cpp-sanitizers/ub-failure-patterns.md` (signed
overflow, misaligned access, null deref, shift / float-cast overflow, …). Treat it as the C/C++
extension of the table above. Remember the **run-scope caveat**: a sanitizer build only catches UB on
paths its tests actually execute — a binary built but not `add_test`-registered is silently skipped (the
T2 trap). Cross-check with `/test-plan` before trusting an "ASan+UBSan clean."
