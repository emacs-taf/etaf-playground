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

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`.
Run `make perf` for the 1413×62 warm row-selection/theme latency gate.

The bundled Research Shelf example installs a deterministic 256-record SQLite
fixture with 12 records per page. Bind `etaf-research-shelf-fixture-size` and
`etaf-research-shelf-page-size` for smaller tests or larger pressure runs. Its
application UI is only a consumer of the generic workspace; activate `Rows N
✎` to enter any value from 1 through 100.
