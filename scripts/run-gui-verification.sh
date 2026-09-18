#!/bin/sh

set -eu

PLAYGROUND_SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PLAYGROUND_DIR=$(dirname "$PLAYGROUND_SCRIPT_DIR")
REPOS_DIR=$(dirname "$PLAYGROUND_DIR")
GENERIC_RUNNER="$REPOS_DIR/etaf/scripts/run-emacs-gui-verification.sh"
SCENARIO_ADAPTER="$PLAYGROUND_SCRIPT_DIR/playground-gui-scenarios.el"
SCENARIO_ENTRY=etaf-playground-gui-scenarios-run-from-environment
SCENARIO_INITIALIZER=""

usage() {
    echo "Legacy isolated GUI runner: creates a separate daemon/frame." >&2
    echo "For the existing Emacs server, see README.md GUI verification." >&2
    echo "usage:" >&2
    echo "  $0 doctor" >&2
    echo "  $0 review RUN_DIR" >&2
    echo "  $0 all [--run-dir DIRECTORY]" >&2
    echo "  $0 task-workbench|research-shelf|flex-reference|grid-reference [--run-dir DIRECTORY]" >&2
    exit 2
}

doctor() {
    [ -x "$GENERIC_RUNNER" ] || {
        echo "generic GUI runner is unavailable: $GENERIC_RUNNER" >&2
        exit 1
    }
    [ -f "$SCENARIO_ADAPTER" ] || {
        echo "Playground scenario adapter is unavailable: $SCENARIO_ADAPTER" >&2
        exit 1
    }
    "$GENERIC_RUNNER" doctor
    echo "PLAYGROUND-GUI-ADAPTER DOCTOR PASS"
}

parse_run_dir() {
    SCENARIO_RUN_DIR=""
    while [ "$#" -gt 0 ]; do
        case $1 in
            --run-dir)
                [ "$#" -ge 2 ] || usage
                SCENARIO_RUN_DIR=$2
                shift 2
                ;;
            *) usage ;;
        esac
    done
    if [ -z "$SCENARIO_RUN_DIR" ]; then
        SCENARIO_RUN_DIR=$(mktemp -d /private/tmp/etaf-playground-gui.XXXXXX)
    else
        mkdir -p "$SCENARIO_RUN_DIR"
    fi
}

prepare_fixture() {
    case $SCENARIO_NAME in
        task-workbench)
            SCENARIO_FIXTURE=""
            SCENARIO_ADAPTER="$PLAYGROUND_SCRIPT_DIR/task-workbench-gui-scenarios.el"
            SCENARIO_ENTRY=task-workbench-gui-run-from-environment
            SCENARIO_INITIALIZER=task-workbench-gui-prepare
            ;;
        research-shelf)
            SCENARIO_FIXTURE=""
            ;;
        flex-reference|grid-reference)
            SCENARIO_FIXTURE="$REPOS_DIR/ebox-playground/examples/$SCENARIO_NAME.ebox"
            ;;
        *) usage ;;
    esac
}

run_scenario() {
    echo "Legacy isolated GUI run: a separate test Emacs will be created (see README.md)." >&2
    prepare_fixture
    doctor >/dev/null
    export ETAF_GUI_SCENARIO="$SCENARIO_NAME"
    export ETAF_GUI_FIXTURE="$SCENARIO_FIXTURE"
    set --
    if [ -n "$SCENARIO_INITIALIZER" ]; then
        set -- --initialize-function "$SCENARIO_INITIALIZER"
    fi
    "$GENERIC_RUNNER" run "$SCENARIO_ADAPTER" "$SCENARIO_ENTRY" \
        "$@" \
        --run-dir "$SCENARIO_RUN_DIR" \
        --load-path "$REPOS_DIR/ecss" \
        --load-path "$REPOS_DIR/ebox" \
        --load-path "$REPOS_DIR/etaf" \
        --load-path "$REPOS_DIR/etaf-ui" \
        --load-path "$REPOS_DIR/etaf-db" \
        --load-path "$REPOS_DIR/ebox-playground" \
        --load-path "$REPOS_DIR/ebox-playground/scripts" \
        --load-path "$PLAYGROUND_DIR" \
        --load-path "$PLAYGROUND_SCRIPT_DIR" \
        --load-path "$PLAYGROUND_DIR/examples"
}

[ "$#" -ge 1 ] || usage
COMMAND=$1
shift

case $COMMAND in
    doctor)
        [ "$#" -eq 0 ] || usage
        doctor
        ;;
    review)
        [ "$#" -eq 1 ] || usage
        "$GENERIC_RUNNER" review "$1"
        ;;
    all)
        parse_run_dir "$@"
        ALL_RUN_ROOT=$SCENARIO_RUN_DIR
        for SCENARIO_ITEM in task-workbench research-shelf flex-reference grid-reference; do
            "$0" "$SCENARIO_ITEM" --run-dir "$ALL_RUN_ROOT/$SCENARIO_ITEM"
        done
        echo "PLAYGROUND-GUI ALL CAPTURED root=$ALL_RUN_ROOT"
        ;;
    task-workbench|research-shelf|flex-reference|grid-reference)
        SCENARIO_NAME=$COMMAND
        parse_run_dir "$@"
        run_scenario
        ;;
    *) usage ;;
esac
