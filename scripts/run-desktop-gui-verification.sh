#!/bin/sh

# Run the ETAF Desktop GUI adapter against the user's existing graphical Emacs
# server.  This script never starts, stops, activates or creates an Emacs.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PLAYGROUND_DIR=$(dirname "$SCRIPT_DIR")
ROOT_DIR=$(dirname "$PLAYGROUND_DIR")
ADAPTER="$SCRIPT_DIR/desktop-gui-scenarios.el"
EMACSCLIENT_BIN=${EMACSCLIENT:-emacsclient}
GUI_TIMEOUT=${GUI_TIMEOUT:-180}

usage() {
    echo "usage: $0 doctor | run [--scenario shell|demo] [--run-dir DIRECTORY] | review DIRECTORY" >&2
    exit 2
}

require_file() {
    [ -f "$1" ] || { echo "required file is missing: $1" >&2; exit 1; }
}

probe_server() {
    python3 - "$EMACSCLIENT_BIN" <<'PY'
import subprocess
import sys

client = sys.argv[1]
expression = "(list :pid (emacs-pid) :graphic (display-graphic-p) :visible (frame-visible-p (selected-frame)) :buffer (buffer-name (window-buffer (selected-window))))"
try:
    result = subprocess.run([client, "--eval", expression], capture_output=True,
                            text=True, timeout=10)
except (OSError, subprocess.TimeoutExpired) as error:
    print(f"existing graphical Emacs server is unavailable: {error}", file=sys.stderr)
    raise SystemExit(1)
if result.returncode or ":graphic t" not in result.stdout or ":visible t" not in result.stdout:
    print(result.stderr.strip() or result.stdout.strip() or "server is not graphical and visible", file=sys.stderr)
    raise SystemExit(1)
print(result.stdout.strip())
PY
}

doctor() {
    command -v "$EMACSCLIENT_BIN" >/dev/null 2>&1 || {
        echo "emacsclient is unavailable: $EMACSCLIENT_BIN" >&2
        exit 1
    }
    require_file "$ADAPTER"
    require_file "$ROOT_DIR/etaf/scripts/emacs-gui-verifier.el"
    require_file "$ROOT_DIR/etaf/scripts/capture-emacs-window.sh"
    probe_server
    echo "ETAF-DESKTOP GUI DOCTOR PASS"
}

run_scenario() {
    RUN_DIR=""
    SCENARIO=shell
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --scenario)
                [ "$#" -ge 2 ] || usage
                case "$2" in
                    shell|demo) SCENARIO=$2 ;;
                    *) echo "unknown Desktop GUI scenario: $2" >&2; usage ;;
                esac
                shift 2
                ;;
            --run-dir)
                [ "$#" -ge 2 ] || usage
                RUN_DIR=$2
                shift 2
                ;;
            *) usage ;;
        esac
    done
    if [ -z "$RUN_DIR" ]; then
        RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/etaf-desktop-gui.XXXXXX")
    else
        mkdir -p "$RUN_DIR"
    fi
    if [ -e "$RUN_DIR/manifest.jsonl" ] || [ -e "$RUN_DIR/result.json" ]; then
        echo "run directory already contains GUI evidence: $RUN_DIR" >&2
        exit 1
    fi
    doctor >/dev/null
    # Load once into the existing server and schedule a timer.  The command
    # returns before the ordered verifier actions run, allowing redisplay and
    # native mouse keymaps to process every checkpoint.
    python3 - "$EMACSCLIENT_BIN" "$ADAPTER" "$RUN_DIR" "$SCENARIO" <<'PY'
import subprocess
import sys
import json

client, adapter, run_dir, scenario = sys.argv[1:]
root = __import__('pathlib').Path(adapter).parents[2]
load_paths = [root / name for name in
              ("ecss", "ebox", "etaf", "etaf/scripts", "etaf-ui",
               "etaf-desktop", "etaf-playground", "etaf-playground/scripts")]
paths_form = "(dolist (path '(%s)) (add-to-list 'load-path path))" % \
    " ".join(json.dumps(str(p)) for p in load_paths)
form = f"(progn {paths_form} (load {json.dumps(adapter)} nil t t) (etaf-desktop-gui-run {json.dumps(run_dir)} '{scenario}))"
try:
    result = subprocess.run([client, "--eval", form], capture_output=True,
                            text=True, timeout=15)
except (OSError, subprocess.TimeoutExpired) as error:
    print(f"could not schedule Desktop GUI scenario: {error}", file=sys.stderr)
    raise SystemExit(1)
if result.returncode:
    print(result.stderr.strip() or result.stdout.strip(), file=sys.stderr)
    raise SystemExit(result.returncode or 1)
print(result.stdout.strip())
PY
    end=$(( $(date +%s) + GUI_TIMEOUT ))
    while [ "$(date +%s)" -lt "$end" ]; do
        if [ -f "$RUN_DIR/result.json" ]; then
            status=$(python3 - "$RUN_DIR/result.json" <<'PY'
import json, sys
try:
    print(json.loads(open(sys.argv[1], encoding="utf-8").read()).get("status", "running"))
except (OSError, ValueError):
    print("running")
PY
)
            case "$status" in
                running) ;;
                passed)
                    echo "ETAF-DESKTOP GUI ASSERTIONS PASS run-dir=$RUN_DIR"
                    echo "Visual review required: inspect frames/*.png and target buffer freshness."
                    return 0
                    ;;
                *)
                    cat "$RUN_DIR/result.json" >&2
                    echo "ETAF-DESKTOP GUI ASSERTIONS FAIL run-dir=$RUN_DIR" >&2
                    return 1
                    ;;
            esac
        fi
        sleep 1
    done
    echo "ETAF-DESKTOP GUI scenario timed out: $RUN_DIR" >&2
    return 2
}

review_run() {
    [ "$#" -eq 1 ] || usage
    RUN_DIR=$1
    require_file "$RUN_DIR/result.json"
    require_file "$RUN_DIR/manifest.jsonl"
    status=$(python3 - "$RUN_DIR/result.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["status"])
PY
)
    [ "$status" = passed ] || { echo "functional GUI assertions did not pass: $status" >&2; exit 1; }
    count=$(find "$RUN_DIR/frames" -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -gt 0 ] || { echo "no checkpoint screenshots found" >&2; exit 1; }
    echo "ETAF-DESKTOP GUI REVIEW INPUT run-dir=$RUN_DIR screenshots=$count"
    echo "Inspect every checkpoint image and verify target freshness before claiming visual acceptance."
}

[ "$#" -ge 1 ] || usage
case "$1" in
    doctor) shift; [ "$#" -eq 0 ] || usage; doctor ;;
    run) shift; run_scenario "$@" ;;
    review) shift; review_run "$@" ;;
    *) usage ;;
esac
