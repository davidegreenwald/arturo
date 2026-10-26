#!/usr/bin/env bash

set -euo pipefail

# profile.sh ===================================================================
# What it does:
# - Tier-2 profiling (ADR-005): records a Time Profiler trace of the built app
#   headlessly, exports the time-profile table to XML, and writes a small
#   summary JSON to traces/summary.json. Agent-runnable deep dive.
#
# Requirements:
#   - Xcode's xctrace (xcrun)
#   - A built app: run `make verify` first (products land in .build/DerivedData)
#   - A normal (non-sandboxed) terminal; Developer Tools TCC permission.
#     Under restrictive sandboxes xctrace fails with a kernel MAC policy error.
#
# Escalation path (Tier 3): open the .trace in Instruments — see
# docs/performance.md (ships in M3).

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Record a headless Time Profiler capture of Arturo and summarize it.

Usage: profile.sh [--seconds N] [--app PATH]

Options:
  --seconds N   Recording duration in seconds (default: 5)
  --app PATH    Path to the .app bundle to launch
                (default: .build/DerivedData/Build/Products/Debug/Arturo.app)

Output:
  traces/profile.trace      raw capture (open in Instruments for Tier 3)
  traces/time-profile.xml   exported time-profile table
  traces/summary.json       machine-readable summary (sample count, paths)

Example:
  scripts/profile.sh --seconds 10
HELP
    exit 0
fi

## Configuration ===============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

SECONDS_TO_RECORD=5
APP_PATH="${ROOT}/.build/DerivedData/Build/Products/Debug/Arturo.app"

while [ $# -gt 0 ]; do
    case "$1" in
        --seconds)
            SECONDS_TO_RECORD="${2:?--seconds requires a value}"
            shift 2
            ;;
        --app)
            APP_PATH="${2:?--app requires a value}"
            shift 2
            ;;
        *)
            echo "Usage: profile.sh [--seconds N] [--app PATH]" >&2
            exit 2
            ;;
    esac
done

TRACE_DIR="${ROOT}/traces"
TRACE_FILE="${TRACE_DIR}/profile.trace"
XML_FILE="${TRACE_DIR}/time-profile.xml"
SUMMARY_FILE="${TRACE_DIR}/summary.json"

BIN_PATH="${APP_PATH}/Contents/MacOS/$(basename "${APP_PATH}" .app)"

## Script ======================================================================

if [ ! -d "${APP_PATH}" ]; then
    echo "✗ app not built yet: ${APP_PATH}" >&2
    echo "  run 'make verify' first, or pass --app /path/to/App.app" >&2
    exit 1
fi

if [ ! -x "${BIN_PATH}" ]; then
    echo "✗ executable not found inside app bundle: ${BIN_PATH}" >&2
    exit 1
fi

mkdir -p "${TRACE_DIR}"
rm -f "${TRACE_FILE}" "${XML_FILE}"

echo "Recording Time Profiler for ${SECONDS_TO_RECORD}s: ${BIN_PATH}"
# --launch -- must be the LAST option; everything after -- is the target cmdline.
xcrun xctrace record \
    --template 'Time Profiler' \
    --time-limit "${SECONDS_TO_RECORD}s" \
    --output "${TRACE_FILE}" \
    --no-prompt \
    --launch -- "${BIN_PATH}"

echo "Exporting time-profile table"
xcrun xctrace export \
    --input "${TRACE_FILE}" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
    --output "${XML_FILE}"

SAMPLE_COUNT=$(grep -c '<row' "${XML_FILE}" 2> /dev/null || echo 0)

cat > "${SUMMARY_FILE}" <<JSON
{
  "tool": "xctrace Time Profiler",
  "recorded_seconds": ${SECONDS_TO_RECORD},
  "sample_rows": ${SAMPLE_COUNT},
  "trace": "traces/profile.trace",
  "xml": "traces/time-profile.xml",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

echo "✓ wrote ${SUMMARY_FILE} (${SAMPLE_COUNT} sample rows)"
echo "  Tier 3 escalation: open ${TRACE_FILE} in Instruments (docs/performance.md)"
