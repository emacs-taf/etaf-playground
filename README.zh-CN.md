# etaf-playground

`etaf-playground` 是 ETAF 的可运行示例应用。核心示例只依赖 `etaf`；需要时才通过可选入口加载 `etaf-ui`。它不调用 Ebox 私有实现，也不依赖 `ebox-playground`。

```elisp
(require 'etaf-playground)
(etaf-playground-open)
```

在该目录运行 `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
