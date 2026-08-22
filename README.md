# ETAF Playground

The Playground exposes one canonical product example: the
`examples/research-shelf.etaf` and `examples/research-shelf.el` pair.

The `.etaf` file is inert, validated structural composition data. The same-
basename companion owns Components, state, theme, storage, events, and
lifecycle. `etaf-playground.el` is a reusable pair framework: it owns only
registration, safe loading, mounting, reset, close, and verification entry
points. `etaf-playground-catalog.el` is the replaceable deployment catalog;
business Components, database schemas, palettes, refs, and handlers
must stay in the companion. Compose and reuse public ETAF/`etaf-ui` contracts
before adding abstractions.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`.
Run `make perf` for the 1413×62 warm row-selection/theme latency gate.

The example installs a deterministic 256-record SQLite fixture with 12 records
per page. Bind `etaf-research-shelf-fixture-size` and
`etaf-research-shelf-page-size` for smaller tests or larger pressure runs.
In the UI, activate `Rows N ✎` to enter any value from 1 through 100. The
workspace is one responsive wrapping Flex composition: three columns when
wide, rail/list plus wrapped detail at medium widths, and vertical when narrow.
