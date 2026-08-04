# etaf-playground

`etaf-playground` is the runnable example application for ETAF. The core example depends only on `etaf`; the optional UI example loads `etaf-ui` when requested. It never imports Ebox internals and it is independent from `ebox-playground`.

```elisp
(require 'etaf-playground)
(etaf-playground-open)
```

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs` from this directory.
