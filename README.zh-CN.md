# ETAF Playground

Playground 只公开一个标准产品示例：
`examples/operations-console.etaf` 与 `examples/operations-console.el` 配对。

`.etaf` 是只读、经过白名单验证的静态组合数据；同名 companion 负责
Component、状态、Context、Theme、Behavior、Data、Resource、Action 与生命周期。
`etaf-playground-open/reset/close` 是唯一挂载边界。

验证命令：`make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
