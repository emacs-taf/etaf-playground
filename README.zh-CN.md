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

Showcase 只使用 ETAF 公共 API，演示响应式 Flex 外壳、根画布背景与局部面板背景的分层、基于 Context 的主题值、响应式状态、内存 Data Controller、带 key 的行以及公共事件分发。它沿用 Ebox Flex 参考示例的暖白纸张、陶土色、鼠尾草绿、蓝色与紫色视觉语言，同时保证亮色和暗色主题中的文字可读性。

最外层 shell 是唯一的 viewport 宽度 owner。它测量窗口正文的真实可用宽度，并为 Emacs 右侧续行标记预留一个字符单元；内部 Flex 区域通过换行适配，不再重复计算 viewport 宽度。该布局会在紧凑 GUI 窗口到全屏桌面宽度之间进行视觉验证。`etaf-playground-open-ui` 仍然是展示官方 `etaf-ui` 目录的较小可选示例；它不代表当前组件目录已经达到旧架构的组件数量与能力。

在该目录运行 `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
