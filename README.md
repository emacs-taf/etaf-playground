# ETAF Playground

ETAF Playground is a generic authoring workspace: the left side edits one
same-basename application's sources and the right side mounts its live ETAF
preview. The framework discovers examples from files; it does not contain a
business catalog or require a concrete application.

Each example follows this contract:

- `examples/NAME.etaf` — one inert structural form;
- `examples/NAME.el` — the companion Components, state, effects, and root
  factory (`etaf-NAME-root` by convention);
- `examples/NAME.ecss` — optional inert `(styles ...)` presentation rules.

Run `M-x etaf-playground-open` to open the default example. The source header
has clickable `ETAF`, `EL`, and `ECSS` buttons. `C-c 1/2/3` (or
`C-c C-1/C-2/C-3`) switches the source; `C-c C-c` renders the current source
into the right-hand preview. Saving a source file also refreshes by default.
`etaf-playground-register-example` is available when a companion needs a
non-conventional root or feature name.

ETAF Playground 0.2.2 declares ETAF 0.2.1, ETAF UI 0.1.0, and ETAF SQLite
0.1.0 so the bundled Research Shelf companion has a complete install closure.

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
mode.  The ETAF/Ebox/TP runtime is loaded when a preview is refreshed or
mounted.  Runtime use requires TP 1.0.1 or newer so `tp-transaction.el` and the
Host final-accept contract are present.

The companion registers `:reload-on-refresh t`, so saving the `.el`, `.etaf`, or
`.ecss` source and refreshing reloads the complete consumer before the next
mount.

## Repeatable Emacs 31.1 GUI verification

Use the user's running graphical Emacs server for current GUI acceptance.
Connect with `emacsclient`, render into an explicit buffer in the existing
frame, then inspect a capture of that window without changing application focus.
Preserve the user's font,
coding settings and normal GC policy. A missing server is not a reason to
silently start a daemon or create another frame.

With this checkout and its sibling dependencies already on Emacs's load path:

```sh
emacsclient --eval '(progn (require (quote task-workbench)) (wb-open "*Workbench review*"))'
```

The maintained example is `examples/task-workbench.el`; add that directory to
`load-path` before requiring it. For automated interaction checks, load
`scripts/task-workbench-gui-scenarios.el` with its `emacs-gui-verifier` engine
and adapter dependencies available, then use the existing frame:

```elisp
(task-workbench-gui-prepare)
(run-at-time 0.05 nil #'task-workbench-gui-run "/absolute/fresh/evidence-directory")
```

The caller owns window capture and evidence review. The adapter requires fresh
dedicated acceptance buffers and preserves the current rendering backend.
Preparation also preserves application focus; `(task-workbench-gui-prepare t)`
explicitly requests foreground activation. Background Emacs-local actions can
verify app behavior, but their timing does not certify foreground display latency.
When `EBOX_NATIVE_REFLOW_MODULE_PATH` is explicitly set, it requires that exact
compatible module. It does not start a server. Check the mounted Runtime,
action assertions and the actual
images. Screenshots alone do not prove a latency bound or absence of flicker.
See `../etaf/scripts/README.md` for existing-server capture and recording details.

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
Run `make perf` for the fixed 1413×62 batch latency gate. Every scenario performs
five unmeasured warmups followed by 30 measured samples; both p95 and max must
remain at or below 50ms, including Theme and post-resize interactions.
For repeated absolute-latency runs, use `make perf-prepare` once after source
changes, let compilation activity settle, then run `make perf-evaluator` without
rebuilding the dependency graph.

## Performance evidence lanes

Performance evidence has three separate lanes correlated by one
repository/environment/scenario/fixture/build identity:

- The batch latency lane runs the retained Research Shelf 1413×62 evaluator
  with 5 unmeasured warmups and 30 measured samples. Its p95/max 50ms checks
  diagnose regressions in that batch fixture. Batch verifier duration measures
  batch Lisp work, not GUI first paint.
- The trace lane runs a separate instrumented representative invocation. Its
  cost classes, work counters, turns, allocation, and GC data are not inserted
  into the timed latency distribution.
- The GUI lane checks the real Emacs interaction sequence and reviewed images.
  Current acceptance also requires three independent foreground GUI sample sets
  with per-operation p95 and max at or below 50ms, from action callback through
  forced redisplay. This gate remains outstanding. Use the measurement boundary
  in `../etaf/scripts/README.md`, preserving warmups, GC and all samples. Returning
  from redisplay does not certify compositor presentation.

Evidence from one lane supports only that lane's conclusion. A
performance-complete or user-visible-non-regression claim requires the
applicable gates from all three lanes.

The bundled Research Shelf example installs a deterministic 256-record SQLite
fixture with 12 records per page. Bind `etaf-research-shelf-fixture-size` and
`etaf-research-shelf-page-size` for smaller tests or larger pressure runs. Its
application UI is only a consumer of the generic workspace; activate `Rows N
✎` to enter any value from 1 through 100.
