# ETAF Playground

The Playground exposes one canonical product example: the
`examples/operations-console.etaf` and `examples/operations-console.el` pair.

The `.etaf` file is inert, validated static composition data. The companion
owns Components, state, Context, Theme, Behaviors, Data, Resources, Actions,
and lifecycle. `etaf-playground-open`, `etaf-playground-reset`, and
`etaf-playground-close` are the only mounting boundary.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`.
