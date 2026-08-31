#!/bin/sh

set -eu

if [ "$#" -eq 0 ]; then
    echo "usage: $0 COMMAND [ARG ...]" >&2
    exit 2
fi

PERF_LOCK_DIR=${ETAF_PERF_LOCK_DIR:-${TMPDIR:-/tmp}/etaf-performance-evaluator.lock}
PERF_LOCK_WAIT_SECONDS=${ETAF_PERF_LOCK_WAIT_SECONDS:-180}

case $PERF_LOCK_WAIT_SECONDS in
    ''|*[!0-9]*)
        echo "ETAF_PERF_LOCK_WAIT_SECONDS must be a non-negative integer" >&2
        exit 2
        ;;
esac

PERF_LOCK_ACQUIRED=false
PERF_LOCK_WAITED=0

release_lock() {
    if [ "$PERF_LOCK_ACQUIRED" = true ]; then
        rm -f "$PERF_LOCK_DIR/pid"
        rmdir "$PERF_LOCK_DIR" 2>/dev/null || true
    fi
}

trap release_lock EXIT HUP INT TERM

while ! mkdir "$PERF_LOCK_DIR" 2>/dev/null; do
    PERF_LOCK_OWNER=
    if [ -r "$PERF_LOCK_DIR/pid" ]; then
        IFS= read -r PERF_LOCK_OWNER < "$PERF_LOCK_DIR/pid" || PERF_LOCK_OWNER=
    fi
    case $PERF_LOCK_OWNER in
        ''|*[!0-9]*) PERF_LOCK_OWNER= ;;
    esac

    if [ -n "$PERF_LOCK_OWNER" ] &&
       ! kill -0 "$PERF_LOCK_OWNER" 2>/dev/null; then
        rm -f "$PERF_LOCK_DIR/pid"
        rmdir "$PERF_LOCK_DIR" 2>/dev/null || true
        continue
    fi

    if [ "$PERF_LOCK_WAITED" -ge "$PERF_LOCK_WAIT_SECONDS" ]; then
        echo "performance evaluator lock timed out: $PERF_LOCK_DIR" >&2
        exit 1
    fi
    if [ "$PERF_LOCK_WAITED" -eq 0 ]; then
        echo "performance evaluator waiting for exclusive host slot" >&2
    fi
    sleep 1
    PERF_LOCK_WAITED=$((PERF_LOCK_WAITED + 1))
done

PERF_LOCK_ACQUIRED=true
printf '%s\n' "$$" > "$PERF_LOCK_DIR/pid"
echo "performance evaluator acquired exclusive host slot"

"$@"
