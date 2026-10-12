# ETAF Playground

Add the repository root to `load-path` and use `(require 'etaf-playground)`.
[`etaf-playground.el`](etaf-playground.el) documents the supported API; `lisp/` contains internal implementations.

ETAF Playground is a generic authoring workspace: the left side edits one
same-basename application's sources and the right side mounts its live ETAF
preview. The framework discovers examples from files; it does not contain a
business catalog or require a concrete application.

Each example follows this contract:

- `examples/NAME.etaf` — one inert structural form;
- `examples/NAME.el` — the companion Components, state, effects, and root
  factory (`etaf-NAME-root` by convention);
- `examples/NAME.ecss` — optional inert `((SELECTOR PROPERTY VALUE ...) ...)` presentation rules.

Run `M-x etaf-playground-open` to open the default example. The source header
has clickable `ETAF`, `EL`, and `ECSS` buttons. `C-c 1/2/3` (or
`C-c C-1/C-2/C-3`) switches the source; `C-c C-c` renders the current source
into the right-hand preview. Saving a source file also refreshes by default.
`etaf-playground-register-example` is available when a companion needs a
non-conventional root name.

ETAF Playground 0.2.2 declares ECSS 0.1.0, ETAF 0.2.1, ETAF UI 0.1.0, ETAF DB
0.1.0, and ETAF Desktop 0.1.0 (currently using its SQLite backend only for
Research Shelf) so the bundled consumers have a complete install closure.

Preview placement uses the standard Emacs `display-buffer` action stored in
`etaf-playground-display-action`.  The default is a right side window using
half the frame:

```elisp
;; Right preview using 40% of the frame.
(setq etaf-playground-display-action
      '((display-buffer-in-side-window)
        (side . right)
        (window-width . 0.4)))

;; Right preview fixed at 100 columns.
(setq etaf-playground-display-action
      '((display-buffer-in-side-window)
        (side . right)
        (window-width . 100)))

;; Preview in its own frame.
(setq etaf-playground-display-action
      '((display-buffer-pop-up-frame)
        (pop-up-frame-parameters . ((width . 120) (height . 45)))))
```

The low-level `etaf-playground-mount-example` API remains available for batch
tests and consumers that only need a preview buffer. Business Components,
database schemas, palettes, refs, and handlers stay in the example companion.

Research Shelf is small enough to keep its complete executable companion in one
`.el` file. Its sections are separated by comments while the Playground entry
files remain easy to discover:

```text
examples/research-shelf.etaf  # inert structure source
examples/research-shelf.ecss  # inert style source
examples/research-shelf.el    # DATA / THEME / STATE / VIEW / ROOT sections
```

Opening an inert `.etaf` or `.ecss` source loads only its lightweight editing
mode. The ETAF/Ebox runtime loads when a preview is refreshed or mounted.

The companion registers `:reload-on-refresh t`, so saving the `.el`, `.etaf`, or
`.ecss` source and refreshing reloads the complete consumer before the next
mount. Direct preview mounts reuse the same source or compiled companion
already loaded in Emacs, including companions preloaded by an application or
benchmark. An unrelated library with the same feature name is a separate file.

## ETAF Desktop consumer

Evaluate `(etaf-playground-open "desktop")` to mount the independent
`etaf-desktop` application through the generic Playground workspace. The example
contains two text windows and demonstrates the application-owned title drag,
resize, z-order, minimize and restore policies. Playground only supplies source
discovery and lifecycle; window state and operations remain in `etaf-desktop`.

For the real GUI acceptance of the Desktop host, use the existing graphical
Emacs server; the command never starts or stops another Emacs:

```sh
make gui-desktop
scripts/run-desktop-gui-verification.sh run --scenario demo
scripts/run-desktop-gui-verification.sh review /tmp/etaf-desktop-gui.XXXXXX
```

Pass `--run-dir DIRECTORY` to `run-desktop-gui-verification.sh run` when the
evidence location must be stable. `--scenario shell` is the default, including
for `make gui-desktop`. Its 26 checkpoints use static text applications to check
rendered title-bar and resize-handle mouse events, workspaces, window lifecycle,
app-error isolation, tiling and settings. Settings checks include the compact
panel, stable background and row heights, minibuffer spacing edits, persisted
values, reset and focus return.

`--scenario demo` instead mounts the maintained six-app Desktop demo: Notes,
Tasks, Calculator, Clock, Chat and Monitor. It checks real app controls and
window/workspace transitions with the Clock timer active, including minimizing
and restoring the Clock. It sends every default desktop shortcut through the
buffer keymap and exercises horizontal and vertical splitters through their
native drag bindings, including separate motion turns, reversal, limits, tile
swaps and retained split ratios. The shell fixture does not cover those
application interactions; run both scenarios for Desktop acceptance.

Both scenarios measure a standard text row in the actual target buffer before
mounting, retaining the user's font and line spacing. Checkpoints reject taller
physical rows; focus changes and every Settings tab also check that stationary
window Hosts keep their pixel Y positions. Shorter border rows do not raise the
standard text-height limit.

The runner honors `EMACSCLIENT` and bounds each run with `GUI_TIMEOUT` (180
seconds by default). Each fresh evidence directory receives `manifest.jsonl`,
`result.json`, and window-only checkpoint PNGs. A passed result certifies the
scenario's functional assertions; inspect every PNG before claiming visual
acceptance. Neither a pass nor the external timeout certifies interaction latency.

## Repeatable Emacs 31.1 GUI verification

Use the user's running graphical Emacs server for current GUI acceptance.
Connect with `emacsclient`, render into an explicit buffer in the existing
frame, then inspect a capture of that window without changing application focus.
Preserve the user's font,
coding settings and normal GC policy. A missing server is not a reason to
silently start a daemon or create another frame.

The legacy isolated runner remains available for the remaining scenarios:

```sh
scripts/run-gui-verification.sh research-shelf
```

The engine writes window screenshots, `manifest.jsonl`, and an atomic
`result.json` into the evidence directory. A passed result certifies the action
assertions; inspect the screenshots separately for appearance. The adapter reads
public Host/selector queries and displayed values. Counts clipped out of the
viewport are recorded as null in checkpoint metadata; actions still require
their expected counts to be displayed. The adapter requires fresh dedicated
acceptance buffers and preserves the current rendering backend. Background
Emacs-local actions can verify app behavior, but their timing does not certify
foreground display latency.
When `EBOX_NATIVE_REFLOW_MODULE_PATH` is explicitly set, it requires that exact
compatible module. It does not start a server. Check the mounted Runtime,
action assertions and the actual
images. Screenshots alone do not prove a latency bound or absence of flicker.
See [how a change is verified](https://etaf.top/extending-the-framework/#how-a-change-is-verified)
for existing-server capture and recording details.

The following commands are **legacy isolated-environment tools**, retained for
explicit requests to use a separate test Emacs. They are not the default
existing-server workflow:

```sh
make gui-doctor
make gui-research
make gui-flex
make gui-grid
# Or capture all four sequentially in isolated test instances:
make gui-all
```

The reusable engine and process runner live in `../etaf/scripts/`. They know
only Scenario, Action, Context, checkpoint, recording, and evidence contracts.
`scripts/playground-gui-scenarios.el` is a thin adapter layer: Research Shelf
defines its application actions, while Flex and Grid are two inputs to the same
Ebox reference scenario factory. Adding another application does not create a
second daemon/recording/checkpoint implementation.

The Research Shelf scenario also closes its preview and mounts a fresh Runtime
against the same SQLite file. It reselects the edited record and reloads the
library, requiring the saved progress and 256-record count to remain unchanged.

Each scenario creates a unique named daemon, disables native-comp JIT, loads
the sibling repositories explicitly, creates one GUI frame, activates Emacs
from the controlling shell, records through a PTY-backed macOS screen recorder,
runs mount/resize/scroll/interaction checkpoints, writes screenshots and a
manifest, then shuts down every process it created. Flex and Grid are read from
their current `ebox-playground` working files so the gate verifies the exact
code a user is testing. The runner never writes, stages, restores, or otherwise
mutates either fixture.

A fresh capture intentionally reports `INCOMPLETE` until a human or agent has
inspected `report.md`, `contact-sheet.png`, and its selected endpoint images.
After that temporal review, finalize the exact run directory:

```sh
scripts/run-gui-verification.sh review /private/tmp/etaf-playground-gui.XXXXXX
```

For this legacy capture bundle, only `VERDICT=PASS` certifies its review.
This verdict is not required by the separate existing-server workflow.
Assertion failure, a black segment,
missing recording, wrong buffer, split window, stale frame, or missing temporal
review remains fail-closed.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`.

## Performance

`benchmarks/performance-scenarios.el` registers the Research Shelf interactions
with the workspace performance tool. Each scenario mounts the example against a
fresh SQLite fixture and repeats one public event: row selection, theme toggle,
filter, page change and resize. Batch runs use a fixed 1413×62 viewport; GUI
runs follow the displaying window.

```sh
make perf-list
make perf-check PERF_ARGS='--samples 30 --sets 3 --output-dir /tmp/shelf-perf'
```

Row selection, theme and resize must fit one 16 ms frame. Filter and page
replace a whole page of keyed rows and have a 33 ms budget. The targets call the workspace's `scripts/performance.py`; its manual
describes GUI mode, baselines and diagnosis passes.

The bundled Research Shelf example installs a deterministic 256-record SQLite
fixture with 12 records per page. Bind `etaf-research-shelf-fixture-size` and
`etaf-research-shelf-page-size` for smaller tests or larger pressure runs. Its
application UI is only a consumer of the generic workspace; activate `Rows N`
to enter any value from 1 through 100.

## Development

After cloning, run `make setup-hooks`. Before submitting a change, run `make check`; `make structure-check` is the fast organization gate.

`make check` runs structure checks, compilation and the public acceptance scenarios listed in [tests/acceptance.json](tests/acceptance.json). `make test` runs the same public API suite. The inventory covers every maintained Lisp test. GUI and performance checks use separate targets.

## Source layout

Add the repository root to `load-path` and require `etaf-playground`. The root entry
loads the implementation in `lisp/` and documents the supported public APIs in
its Commentary. Package archives include both the root entry and `lisp/`.
