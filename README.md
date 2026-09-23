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
ETAF requires Ebox SPI v3 for coordinated publication and Host final acceptance.

The companion registers `:reload-on-refresh t`, so saving the `.el`, `.etaf`, or
`.ecss` source and refreshing reloads the complete consumer before the next
mount.

## Task Workbench

Evaluate `(etaf-playground-open "task-workbench")` for source and preview, or
`(etaf-playground-mount-example "*Tasks*" "task-workbench")` for a standalone
preview. Each instance starts with 100 independent in-memory tasks. Select a
row, edit Title or State through native input, then Save changes or Cancel.
Blank titles disable saving; edits remain drafts until saved. Switching tasks
or filters asks before discarding an unsaved draft. TAB and RET reach the same
controls as the mouse. Reads and writes complete through native asynchronous
callbacks over one instance-owned memory source. The Data service selector
arranges read failures, rejected writes, refresh failures, reversed search
completion, timeout or a lost save receipt. Pending writes prevent duplicate
submission; a rejected write retains the draft for retry. After a committed write,
Retry read only refreshes data. An unknown receipt requires reading back the
record before adopting its saved value. The displayed saved revision changes
only on writes, so read recovery can be checked without replaying a save.
Service health separately demonstrates asynchronous Resource loading.
Each row's Actions menu opens editing or requests deletion of a completed task.
Declining confirmation preserves the task and returns focus to the menu entry.
A persistent component error boundary remains an ecosystem requirement.
Workbench exposes `wb-task-N` row Host references through DataGrid's `:row-ref`
input, where N is the task ID. Interaction drivers can address tasks without inspecting UI internals.

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
scripts/run-desktop-gui-verification.sh review /tmp/etaf-desktop-gui.XXXXXX
```

Pass `--run-dir DIRECTORY` to `run-desktop-gui-verification.sh run` when the
evidence location must be stable. The adapter mounts a fresh desktop, sends
rendered title-bar and resize-handle mouse events, switches workspaces, checks
maximize/minimize/restore and app-error isolation, and exercises the tiling
layout contract. Settings checkpoints check the centered compact panel,
unchanged desktop background and row heights, Layout-tab spacing edits through
the real minibuffer, persisted values, reset and focus return on dismissal.
It writes `manifest.jsonl`, `result.json`, and one window-only
PNG per checkpoint. A passed result certifies functional assertions; inspect
every PNG in the run directory before claiming visual acceptance.

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

The automated traversal uses keyboard pagination at its first forward and last
backward steps, with mouse pagination between them, and checks every task identity.
The maintained example is `examples/task-workbench.el`; add that directory to
`load-path` before requiring it. For automated interaction checks, load
`scripts/task-workbench-gui-scenarios.el` with its `emacs-gui-verifier` engine
and adapter dependencies available, then use the existing frame:

```elisp
(task-workbench-gui-prepare)
(run-at-time 0.05 nil #'task-workbench-gui-run "/absolute/fresh/evidence-directory")
```

To quickly recheck selected-detail retirement and asynchronous read recovery,
use a fresh prepared target and pass `'read-recovery` as the final argument:

```elisp
(task-workbench-gui-prepare)
(run-at-time 0.05 nil #'task-workbench-gui-run
             "/absolute/fresh/recovery-evidence" 'read-recovery)
```

This reuses nine full-scenario actions for search, timeout, cancellation,
restored details and empty results. It keeps the same assertions and screenshots;
the complete run remains required for the other workflows.

The engine writes window screenshots, `manifest.jsonl`, and an atomic
`result.json` into the evidence directory. A passed result certifies the action
assertions; inspect the screenshots separately for appearance. The adapter reads
public Host/selector queries and displayed values. Counts clipped out of the
viewport are recorded as null in checkpoint metadata; CRUD and filtering actions
still require their expected counts to be displayed. The adapter requires fresh
dedicated acceptance buffers and preserves the current rendering backend.
Preparation also preserves application focus; `(task-workbench-gui-prepare t)`
explicitly requests foreground activation. Background Emacs-local actions can
verify app behavior, but their timing does not certify foreground display latency.
When `EBOX_NATIVE_REFLOW_MODULE_PATH` is explicitly set, it requires that exact
compatible module. It does not start a server. Check the mounted Runtime,
action assertions and the actual
images. Screenshots alone do not prove a latency bound or absence of flicker.
See the [ETAF GUI verification guide](https://gitea.gklazycat.heiyu.space/geekinney/etaf/src/branch/main/docs/manual.md#gui-verification-tools)
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
Run `make perf` for the fixed 1413×62 batch latency gate. Every scenario performs
five unmeasured warmups followed by 30 measured samples; both p95 and max must
remain at or below 50ms, including Theme and post-resize interactions.

Workbench has a separate fast batch workload after `make check` has compiled
this checkout and its dependencies:

```sh
ETAF_WORKBENCH_BENCHMARK_OUTPUT=/tmp/workbench-before.json make perf-workbench
# After the next change and compilation:
ETAF_WORKBENCH_BENCHMARK_OUTPUT=/tmp/workbench-after.json make perf-workbench
python3 scripts/compare-workbench-performance.py /tmp/workbench-before.json /tmp/workbench-after.json
```

Each of row toggle, theme toggle and Add-button focus starts with an independent
100-task, 10-row application, then runs 5 warmups and 30 measured activations.
Every activation checks the published result outside the timed interval. The
workload resets focus to the theme control before each Add-button focus sample,
outside the timed interval, so each measured activation must change the focused Host.
The same reset precedes each independently recorded diagnostic action. Reports
record raw samples, environment and source digests. The comparison recalculates
p95/max from those samples, rejects incompatible or incomplete evidence, and
fails on either a greater-than-2-ms increase or the existing 50-ms limit.
Keep the evaluator unchanged when comparing application revisions. These are
batch dispatch-to-asynchronous-settlement measurements. They include the demo
provider's timer waiting time; row-toggle therefore includes the write and refresh
waits and cannot establish the separate 50-ms local request/delivery budget.
The existing wall limit still reports a failure instead of hiding that wait.
The evaluator identity and timing boundary reject comparisons with old synchronous
reports. Separate request-start and result-delivery latency certification remains
pending, along with foreground latency acceptance. Without an output variable, the command
prints the path of a fresh temporary report. Application messages go to a
separate temporary log; the terminal shows timings, verdict and artifact paths.

To locate an expensive operation, run `make profile-workbench SCENARIO=row-toggle`
(also `theme-toggle` or `focus-add`). It runs two fresh instances of the same
checked workload: public provider-stage recording first, CPU sampling second.
Each pass warms up five times and diagnoses ten actions by default. Recording
and CPU sampling cover each action through asynchronous settlement; operation
records share an action index, including result-delivery publications. The compact
output ranks overlapping stage means and the nearest named package caller of
each CPU sample. Caller buckets are disjoint; anonymous and primitive frames
are attributed to their nearest named caller, while GC/runtime-only samples
may have none. The JSON report
retains each operation, sanitized sampled stacks, self/inclusive sample weights,
function source files, loaded revisions, local changes and source hashes.
Use `ETAF_WORKBENCH_PROFILE_OUTPUT` for an explicit report path and
`ETAF_WORKBENCH_PROFILE_SAMPLES=1..100` to choose the action count.
Stacks retain up to 256 frames by default; set
`ETAF_WORKBENCH_PROFILE_STACK_DEPTH=16..1024` to change this limit. The report
marks stacks reaching the limit and prints their sample weight. Such stacks
may omit outer callers, so inclusive rankings can undercount them; increase
the depth before using those rankings to attribute cost to an architectural layer.
Inspect the retained stacks and self/inclusive counts to distinguish a caller's
own work from its descendants; an inclusive total is not that function's overhead.
Function samples are statistical evidence, not call counts or exact function
durations; anonymous closures may remain unnamed. Very short actions may produce
no CPU samples and return a diagnostic failure. Investigate the owning provider
and repeated work along its callers, then use the separate **unprofiled**
`perf-workbench` comparison to validate the fix. Instrumented runs cannot pass
the latency or GUI acceptance gates.

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
  in the [ETAF GUI measurement guide](https://gitea.gklazycat.heiyu.space/geekinney/etaf/src/branch/main/docs/manual.md#measuring-an-existing-gui-action),
  preserving warmups, GC and all samples. Returning
  from redisplay does not certify compositor presentation.

Evidence from one lane supports only that lane's conclusion. A
performance-complete or user-visible-non-regression claim requires the
applicable gates from all three lanes.

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
