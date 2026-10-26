# ADR-005: Performance — budgets for a full-screen viewer

**Status:** Accepted · **Date:** 2026-08-25 · **Revised:** 2026-10-25

## Context
Arturo's whole value proposition is that it feels like the photographs, not like
software. A slideshow that stutters on a page advance, or that grows memory
while it plays, fails at the one thing it is for. Performance therefore needs
numbers rather than impressions.

The earlier version of this ADR was written for a menu-bar app family and set
budgets for panel latency and idle cost — surfaces Arturo does not have. It also
described `OSSignposter` spans and XCTest baseline tests that were never
implemented. This revision describes the surfaces that actually exist and is
explicit about which parts are enforced today and which are intent.

## Decision

### Budgets
These are the numbers that matter for a full-screen photo viewer:

- **Cold launch** under 500 ms to an interactive window.
- **Page advance** under 100 ms from key press or timer to the new photographs
  being fully drawn at display size. This is the hot path.
- **Memory ceiling** that does not grow over a long session. The image cache is
  bounded at 9 frames (`ImageStore.swift`), and decoding happens at display size
  rather than full resolution, so a 24 MP JPEG never becomes 96 MB of pixels.
- **Hitch rate** zero during a page transition, including the first advance
  after opening a large folder.
- **Steady-state CPU** near zero between advances, with no disk polling.

### What is enforced today
- Decoding runs off the main actor and is bounded to display size, so the main
  thread never absorbs full-resolution decode cost.
- The cache is capped at a fixed frame count rather than by total bytes, so
  memory is predictable regardless of source resolution. Arrival-order eviction,
  in-flight dedup, and the rule that a decode outliving a cache clear retains
  nothing are pinned by `Tests/AppTests/ImageStoreTests.swift`.
- The hot path is covered by unit tests for rotation, decoding, and the cache
  (`Tests/AppTests/RotationLoopTests.swift`, `ImageDecoderTests.swift`,
  `ImageStoreTests.swift`).

### What is not enforced, and this is a known gap
There are no XCTest performance-baseline tests and no signposts in the codebase.
Nothing in `make verify` would catch a page-advance regression. Two additions
would close it, and neither is required to ship:

1. `OSSignposter` spans around page advance, so Instruments and `xctrace` can
   attribute time without guesswork.
2. An XCTest performance test with a committed baseline on the decode-and-present
   path, run in the scheduled lane rather than the commit gate.

Folder scanning is the exception: it has a committed harness
(`scripts/bench-folder-scan.sh`), ordering assertions in the commit gate, and a
recorded baseline. A sort-key regression that once cost 991 ms at 50,000 files
is now 262 ms, and the ordering tests fail if the comparator changes.

`make profile` provides the Tier-2 entry point below, so the investigation
tooling exists before the regression-detection tooling does. Measured figures,
reproduction commands, and the changes considered and rejected are in
[performance-baseline.md](../performance-baseline.md).

### Tiers
- **Tier 1 — in-gate prevention:** unit tests cover correctness of the hot path.
  Performance baselines are the gap described above.
- **Tier 2 — scriptable deep dive:** `scripts/profile.sh` records Time Profiler
  headlessly (`xcrun xctrace record --template 'Time Profiler' --launch …`),
  exports the `time-profile` table to XML, and writes `traces/summary.json`.
  Needs a non-sandboxed terminal and Developer Tools TCC access.
- **Tier 3 — interactive:** open the `.trace` in Instruments. SwiftUI instrument
  for body counts, Hangs and Hitches for transitions, Allocations for the ceiling.

## Consequences
The memory and main-thread guarantees are real today and are enforced by
construction rather than by test. The latency budgets are documented intent, not
regression-detected facts — a future change could silently breach them. Stating
that plainly is better than implying coverage that does not exist.

## Alternatives considered
Performance benchmarks inside the commit gate — noise and flakiness at commit
time for no benefit; the scheduled lane is the right home. Signposts alone
without baselines — measurement with no threshold regresses silently. Byte-bounded
caches — unpredictable frame counts on mixed-resolution folders, which is the
common case for an iPhone library.
