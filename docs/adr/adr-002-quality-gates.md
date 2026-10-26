# ADR-002: Quality gates — one fast gate, slow lanes separate

**Status:** Accepted · **Date:** 2026-08-25 · **Revised:** 2026-10-24

## Context
"Done" has to be decidable by machine, and fast enough to run at every commit.
Slow suites (UI automation) and slower checks (mutation testing) would make a
commit-time gate unusable, and a gate people bypass is worse than no gate at all.

## Decision
**Fast gate = `make verify` (`scripts/verify.sh`). Exit 0 means done.** This is
exactly what CI runs.

Stages, cheap to expensive:

1. Idempotency: two consecutive `xcodegen generate` runs hash identically.
2. `swiftformat --lint .`
3. `swiftlint --strict`
4. `xcodebuild build` (unsigned — see ADR-004)
5. `xcodebuild test -only-testing:AppTests` (Swift Testing unit suite)

Budget: roughly 120 seconds. CI enforces the gate on every push and pull
request.

**Optional, and deliberately not required:** `make hooks` installs a pre-commit
and pre-push hook that run the same gate locally. It is a convenience for
maintainers, not a contribution requirement, and it replaces any global
`core.hooksPath` you already have. CI is the enforcement point.

**Separate lanes, never in the fast gate:**
- `make test-ui` — UI smoke suite. Slower and it needs an ad-hoc signature.
- `make revert-check FILE=… FILTER=…` — proves a regression test actually dies
  when its fix is reverted.
- `make mutation` — optional mutation testing via `muter`, scheduled only.
- Performance baselines — see ADR-005, which records that these are not yet
  implemented.

Known limitation, accepted: hash-comparison idempotency proves the generator is
deterministic, but it cannot catch "edited sources without regenerating". That
gap is covered by review: if you added a file, check `git status` for an
unexpected `Generated/` diff.

## Consequences
Main stays green by construction, and feedback is under two minutes. The cost is
that UI regressions can reach main unless the slow lane runs before merge, which
is a reviewer responsibility rather than something the build can force.

## Alternatives considered
Everything in one gate — rejected: gates over five minutes get skipped. No gate
and trust the contributor — rejected: agreement is not verification. Mandatory
hooks — rejected: `core.hooksPath` is per-clone, cannot be enforced, and a
120-second pre-commit hook is a strong incentive to use `--no-verify`.
