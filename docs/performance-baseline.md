# Performance baseline

A record of what was measured, on what machine, with what commands, and what was
deliberately not changed. Written so a future maintainer can tell a real
regression from a different machine, and so the decisions not to act are not
re-litigated from scratch.

Date of measurement: 2026-10-24. Machine: Apple Silicon, 10 cores (4
performance), 32 GB RAM, macOS 26.5, Xcode 26.4.1. Absolute numbers are not
portable to other hardware; ratios and orderings are.

## Source of the numbers

Two kinds, and the difference matters:

- **Direct measurements** (folder scan, decode) — standalone harnesses compiled
  against the shipping source files. Reproducible with the commands below.
- **Runtime measurements** (RSS, CPU, launch) — taken by an automated evaluation
  pass that could not use `ps`, `screencapture`, or `task_for_pid` in its
  sandbox. It sampled its own `MACH_TASK_BASIC_INFO` through an injected dylib.
  Directionally sound, but treat absolute RSS as approximate; see Limits.

## What was fixed: folder scan sort keys

`FolderScanner.imageURLs` sorted by deriving `lastPathComponent` **inside** the
sort comparator. That bridges to `NSString` and allocates a `String` on every
comparison — roughly 850,000 allocations for a 50,000-file folder. The fix
derives the key once per file, before sorting. The comparator is unchanged, so
the resulting order is identical.

### Reproduce

```sh
scripts/bench-folder-scan.sh --files 50000 --max-ms 300 --runs 3
```

The script compiles the real `Sources/Features/Slideshow/FolderScanner.swift`
against a synthetic corpus in a temporary directory, so it measures the shipping
code and not a copy. It is intentionally not part of `make verify` — wall-clock
thresholds on shared CI make a commit gate flaky (ADR-002, ADR-005).

### Result

Best of 3 runs, same machine, same corpus:

| Files in folder | Before | After | Speedup |
|---|---|---|---|
| 1,000 | 19.0 ms | 6.6 ms | 2.9x |
| 10,000 | 166.6 ms | 46.2 ms | 3.6x |
| 50,000 | 991.4 ms | 261.9 ms | 3.8x |

Where the time went, at 50,000 files (single cold pass, milliseconds):

| Phase | Cost |
|---|---|
| `contentsOfDirectory` | 57.5 |
| extension filter | 16.9 |
| per-file `isRegularFile` stat | 37.3 |
| **`localizedStandardCompare` sort** | **685.5** |
| (alternative) plain `<` sort | 856.4 |

Two conclusions worth keeping:

1. The sort was ~85% of scan time, not enumeration and not the per-file `stat`.
   Moving the scan off the main actor would have hidden the symptom without
   addressing it.
2. `localizedStandardCompare` is already the fast primitive. Substituting
   `String.compare(_:options: .numeric)` made it **4.7x slower** (3,268 ms at
   50,000 files), because localized comparison is precisely what makes
   `IMG_2` sort before `IMG_10`.

Sort isolation, mean of 3 runs (milliseconds):

| Files | Key in comparator | Key precomputed | `String.compare(.numeric)` |
|---|---|---|---|
| 1,000 | 18.2 | 2.5 | 56.8 |
| 10,000 | 111.7 | 21.5 | 536.9 |
| 50,000 | 696.6 | 130.6 | 3,267.9 |

Ordering is locked by `Tests/AppTests/FolderScannerTests.swift` — every
comparator flip fails four tests, verified by temporarily changing the comparator
to `.orderedDescending`.

## What was measured and deliberately not changed

### Decode ceiling — `SlideshowView.swift:118`

The ceiling is `max(size.height, columnWidth) * displayScale`, which is correct
for the worst-case aspect ratio and oversized for typical ones. Measured against
the six real 6016x6016 HEIC files on this machine, using the shipping
`ImageDecoder`:

| Ceiling | Per-frame decode | 6 concurrent | Per-frame memory | 6 frames |
|---|---|---|---|---|
| 949 px (actual 3-up draw size) | 67.0 ms | 199.5 ms | 3.44 MB | 20.6 MB |
| 1676 px (what 3-up uses) | 55.3 ms | 192.2 ms | 10.72 MB | 64.3 MB |
| 2600 px (what 1-up uses) | 60.2 ms | 207.8 ms | 25.79 MB | 154.7 MB |

Reproduce (system wallpapers differ per machine, so no committed script):

```sh
cat > /tmp/decodebench.swift <<'SWIFT'
import Foundation
@main struct D { static func main() async {
    let dir = "/System/Library/Desktop Pictures"
    let urls = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { $0.hasSuffix(".heic") }.sorted().prefix(6)
        .map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
    for ceiling in [949, 1676, 2600] {
        var bytes = 0
        let t = Date()
        await withTaskGroup(of: Void.self) { g in
            for u in urls { g.addTask {
                if let i = await ImageDecoder.downsample(url: u, maxPixelSize: ceiling) {
                    bytes = i.cgImage.bytesPerRow * i.cgImage.height
                }
            } }
        }
        print(ceiling, Date().timeIntervalSince(t) * 1000, Double(bytes) / 1_048_576)
    }
} }
SWIFT
swiftc -O Sources/Features/Slideshow/ImageDecoder.swift \
       Sources/Features/Slideshow/LoadedImage.swift /tmp/decodebench.swift -o /tmp/decodebench
/tmp/decodebench
```

The finding: **decode time is flat across ceilings; memory scales 7.5x.**
Reducing the 3-up ceiling from 1676 to 949 would save ~7.3 MB per frame with no
latency cost.

Not done, because it changes the image pipeline and carries real risk:

- Sizing from pixel dimensions ignores EXIF orientation. A rotated portrait gets
  sized on the wrong axis and renders soft — unacceptable for a photo viewer.
- Fill mode must still size by `max()`, or every crop goes soft.
- `ImageStore.setMaxPixelSize` holds one ceiling with a 192 px hysteresis guard
  and clears the cache on change. A per-image target means per-image ceilings,
  which is an `ImageStore` redesign, not a tweak.

### Decode concurrency at launch

Three-up requests `visibleImages + nextPageImages`, so six decodes start at once.
Serialising them costs 140–200 ms of launch latency (see the table above:
192.2 ms concurrent vs 331.6 ms serial at 1676 px) to reduce a memory peak that
is invisible on any machine that runs macOS 26. A core-aware bound
(`min(6, activeProcessorCount)`) never binds at 6 on a 10-core machine and so
would be a no-op where it matters least.

Not done: it trades the app's most-noticed latency for an unobserved metric.

### Cache capacity — `ImageStore.swift:19`

`capacity = 9` is flat regardless of column count. At 3 columns that is exactly
right: six frames is the minimum that never blanks during a page advance, and
nine adds one previous page for back-skip. At 1 column it over-retains about
4.5x.

Not done: it is correct where most users are, and the change is only worth making
alongside the ceiling work above.

### Folder scan on the main actor

`SlideshowModel` is `@MainActor` and `open()` calls `FolderScanner.imageURLs`
synchronously, so the scan blocks the main thread. After the sort fix that is
~262 ms at 50,000 files rather than ~991 ms — a visible hitch rather than a
beachball.

Not done: making `open()` async restructures the auto-play and full-screen path,
introduces re-entrancy (two fast ⌘O presses), and makes `SlideshowModel.init`
spawn a task so the window renders empty for a frame before photographs arrive.
All of that cost lands on the median user to improve a case they never hit. The
sort fix captured most of the benefit for none of the risk.

## Runtime profile against ADR-005

| Budget | Measured | Verdict |
|---|---|---|
| Cold launch < 500 ms to interactive window | ~560–640 ms to settled with photographs | Uncertifiable; interactive window is not observable externally |
| Page advance < 100 ms | Incoming page is prefetched and resident | Likely met; no signposts to prove it |
| Memory ceiling, no growth over a long session | 126.2–165.9 MB band over 3 min, no trend | Passes on growth |
| Hitch rate zero | Not measurable without Instruments | Unmeasured |
| Steady CPU near zero between advances | 0.05–0.10%, mean 0.229% | Passes |

Also observed: 144.8 MB steady at 3 columns, 121.6 MB at 1 column, 265.7 MB peak
at launch (638 ms), 202.4 MB mid-advance.

## Limits of this record

- **Absolute RSS understates allocation.** macOS compresses and purges inactive
  backing stores; 1-column RSS of 121.6 MB against a nominal 9 x 25.79 MB cache
  is the clearest example. `footprint` or Instruments Allocations is the real
  figure, and both need `task_for_pid`, which was unavailable.
- **No signposts exist in the code.** Every number here came from external
  harnesses that the next maintainer would have to rebuild. Adding
  `OSSignposter` spans around page advance and one XCTest baseline is the change
  that makes this record reproducible rather than historical — ADR-005 already
  specifies both.
- **The corpus was 13 real photographs, not 77.** `/System/Library/Desktop
  Pictures/` holds 13 `.heic` files plus thumbnails; an earlier count of 77
  included every file in that directory. The scan benchmark uses a synthetic
  corpus and is unaffected; the decode figures come from those 13.
- **Nothing here is a regression test.** These are measurements, not assertions,
  except for the ordering tests in `FolderScannerTests`.

## Reproducing the whole set

```sh
make generate

# Folder scan (committed harness, asserts a threshold)
scripts/bench-folder-scan.sh --files 50000 --max-ms 300 --runs 3

# Ordering guards (in the commit gate)
make test

# Runtime RSS/CPU and decode timings: follow the commands above.
# For a proper allocation figure, run the app under Instruments:
#   Xcode > Open Developer Tool > Instruments > Allocations, attach to Arturo
```
