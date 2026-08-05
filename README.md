# etaf-playground

`etaf-playground` is the runnable example application for ETAF. The core example depends only on `etaf`; the optional UI example loads `etaf-ui` when requested. It never imports Ebox internals and it is independent from `ebox-playground`.

```elisp
(require 'etaf-playground)
(etaf-playground-open)
```

For the complete interactive example, open the Showcase:

```elisp
(require 'etaf-playground)
(etaf-playground-open-showcase)
```

The Showcase is intentionally built only from public ETAF APIs. It demonstrates a Grid shell, a root canvas background with local panel surfaces, Context-based theme values, reactive state, a memory Data Controller, keyed rows, and public event dispatch. The `etaf-playground-open-ui` entry remains the smaller optional example for the official `etaf-ui` catalog.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs` from this directory.
