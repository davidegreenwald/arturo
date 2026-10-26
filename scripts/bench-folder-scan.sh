#!/usr/bin/env bash

set -euo pipefail

# bench-folder-scan.sh =========================================================
# What it does:
# - Times FolderScanner.imageURLs against a synthetic folder of N files.
# - Compiles the real Sources/Features/Slideshow/FolderScanner.swift, so the
#   measurement follows the shipping code rather than a copy of it.
# - Optional --max-ms turns the run into a pass/fail check.
#
# This is a MAINTAINER TOOL and is deliberately NOT part of `make verify`.
# Wall-clock thresholds are machine-dependent and would make the commit gate
# flaky (ADR-002, ADR-005). Run it by hand when changing folder scanning.
#
# Requirements:
#   - swiftc (Xcode or Command Line Tools)
#   - mktemp, trap (macOS built-ins)

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Time Arturo's folder scan against a synthetic corpus.

Usage: bench-folder-scan.sh [OPTIONS]

Options:
  -n, --files <count>   Number of files in the corpus (default: 20000)
  -m, --max-ms <ms>     Fail if the best run exceeds this many milliseconds
  -r, --runs <count>    Timed runs to take; the best is reported (default: 3)
  -h, --help            Show this help message and exit

Exit status 0 on success, 1 if --max-ms was given and exceeded, 2 on bad input.

Example:
  scripts/bench-folder-scan.sh --files 50000 --max-ms 300
HELP
    exit 0
fi

## Configuration ===============================================================

FILE_COUNT=20000
MAX_MS=""
RUNS=3

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n | --files)
            FILE_COUNT="${2:-}"
            shift 2
            ;;
        -m | --max-ms)
            MAX_MS="${2:-}"
            shift 2
            ;;
        -r | --runs)
            RUNS="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: bench-folder-scan.sh [OPTIONS]" >&2
            exit 2
            ;;
    esac
done

case "${FILE_COUNT}" in
    '' | *[!0-9]*)
        echo "Error: --files must be a positive integer" >&2
        echo "Usage: bench-folder-scan.sh [OPTIONS]" >&2
        exit 2
        ;;
esac

if [ -z "${FILE_COUNT}" ] || [ "${FILE_COUNT}" -lt 1 ]; then
    echo "Error: --files must be at least 1" >&2
    exit 2
fi

if [ -n "${MAX_MS}" ]; then
    case "${MAX_MS}" in
        *[!0-9]*)
            echo "Error: --max-ms must be a positive integer" >&2
            exit 2
            ;;
    esac
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="${ROOT}/Sources/Features/Slideshow/FolderScanner.swift"

if [ ! -f "${SCANNER}" ]; then
    echo "Error: cannot find ${SCANNER}" >&2
    exit 1
fi

if ! command -v swiftc > /dev/null 2>&1; then
    echo "Error: swiftc not found. Install Xcode or the Command Line Tools." >&2
    exit 1
fi

## Script ======================================================================

WORK="$(mktemp -d)"
CORPUS="${WORK}/corpus"
HARNESS="${WORK}/main.swift"
BINARY="${WORK}/bench"

cleanup() {
    rm -rf "${WORK}"
}
trap cleanup EXIT

echo "Creating ${FILE_COUNT} files in a temporary corpus"
mkdir -p "${CORPUS}"
python3 - "${CORPUS}" "${FILE_COUNT}" <<'PYTHON'
import os
import sys

corpus, count = sys.argv[1], int(sys.argv[2])
for index in range(count):
    open(os.path.join(corpus, "IMG_%06d.jpg" % index), "wb").close()
PYTHON

echo "Compiling the harness against the shipping FolderScanner"
cat > "${HARNESS}" <<'SWIFT'
import Foundation

let corpus = URL(fileURLWithPath: CommandLine.arguments[1])
let runs = Int(CommandLine.arguments[2]) ?? 3

var best = Double.greatestFiniteMagnitude
var found = 0
for _ in 0 ..< runs {
    let start = Date()
    let urls = (try? FolderScanner.imageURLs(in: corpus)) ?? []
    let elapsed = Date().timeIntervalSince(start) * 1000
    found = urls.count
    best = min(best, elapsed)
}

print(String(format: "%.1f", best))
SWIFT

swiftc -O "${SCANNER}" "${HARNESS}" -o "${BINARY}"

echo "Timing ${RUNS} run(s)"
BEST_MS="$("${BINARY}" "${CORPUS}" "${RUNS}")"

echo "scan of ${FILE_COUNT} files, best of ${RUNS}: ${BEST_MS} ms"

if [ -n "${MAX_MS}" ]; then
    if [ "$(echo "${BEST_MS} > ${MAX_MS}" | bc -l)" = "1" ]; then
        echo "FAIL: ${BEST_MS} ms exceeds the ${MAX_MS} ms threshold" >&2
        exit 1
    fi
    echo "PASS: within the ${MAX_MS} ms threshold"
fi
