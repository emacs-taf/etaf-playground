# etaf-playground

`etaf-playground` 是 ETAF 的可运行示例应用。核心示例只依赖 `etaf`；需要时才通过可选入口加载 `etaf-ui`。它不调用 Ebox 私有实现，也不依赖 `ebox-playground`。

```elisp
(require 'etaf-playground)
(etaf-playground-open)
```

要打开完整的交互示例，使用 Showcase：

```elisp
(require 'etaf-playground)
(etaf-playground-open-showcase)
```

Showcase 只使用 ETAF 公共 API，演示 Grid 外壳、根画布背景与局部面板背景的分层、基于 Context 的主题值、响应式状态、内存 Data Controller、带 key 的行以及公共事件分发。`etaf-playground-open-ui` 仍然是展示官方 `etaf-ui` 目录的较小可选示例。

在该目录运行 `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
