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

The Showcase is intentionally built only from public ETAF APIs. It demonstrates a responsive Flex shell, a root canvas background with local panel surfaces, Context-based theme values, reactive state, a memory Data Controller, keyed rows, and public event dispatch. Its warm paper, terracotta, sage, blue, and violet visual language follows the Ebox Flex reference while remaining readable in both light and dark themes.

The outer shell is the only viewport-width owner. It measures the visible window body, reserves one character cell for Emacs' right-edge continuation indicator, and lets internal Flex sections wrap without repeating viewport arithmetic. The layout is visually verified from compact GUI frames through fullscreen desktop widths. The `etaf-playground-open-ui` entry remains the smaller optional example for the official `etaf-ui` catalog; it is not a claim that the current catalog matches the legacy component inventory.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs` from this directory.
