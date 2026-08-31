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

The companion registers `:reload-on-refresh t`, so saving the `.el`, `.etaf`, or
`.ecss` source and refreshing reloads the complete consumer before the next
mount.

## Repeatable Emacs 31.1 GUI verification

The repository owns one stable real-GUI runner instead of relying on ad-hoc
`emacsclient`, focus, and recording commands:

```sh
make gui-doctor
make gui-research
make gui-flex
make gui-grid
# Or capture all three sequentially:
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

Only `VERDICT=PASS` is valid GUI evidence. Assertion failure, a black segment,
missing recording, wrong buffer, split window, stale frame, or missing temporal
review remains fail-closed.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`.
Run `make perf` for the fixed 1413×62 latency gate. Every scenario performs
five unmeasured warmups followed by 30 measured samples; both p95 and max must
remain at or below 50ms, including Theme and post-resize interactions.
For repeated absolute-latency runs, use `make perf-prepare` once after source
changes, let compilation activity settle, then run `make perf-evaluator` without
rebuilding the dependency graph.

## Performance evidence lanes

Performance evidence has three separate lanes correlated by one
repository/environment/scenario/fixture/build identity:

- The latency lane runs the fixed 1413×62 batch evaluator with 5 unmeasured
  warmups and 30 measured samples. The current active gate requires both p95
  and max to be at or below 50ms for every scenario.
- The trace lane runs a separate instrumented representative invocation. Its
  cost classes, work counters, turns, allocation, and GC data are not inserted
  into the timed latency distribution.
- The GUI lane captures the real Emacs interaction sequence, screenshots, and
  temporal-review verdict. Batch verifier duration is not GUI first paint;
  action-start to forced-redisplay-complete first-paint timing remains a
  separately identified future gate and an observed M0a gap.

Evidence from one lane supports only that lane's conclusion. A
performance-complete or user-visible-non-regression claim requires the
applicable gates from all three lanes.

The bundled Research Shelf example installs a deterministic 256-record SQLite
fixture with 12 records per page. Bind `etaf-research-shelf-fixture-size` and
`etaf-research-shelf-page-size` for smaller tests or larger pressure runs. Its
application UI is only a consumer of the generic workspace; activate `Rows N
✎` to enter any value from 1 through 100.
