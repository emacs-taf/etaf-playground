# ETAF Playground

ETAF Playground 是通用的应用构建工作区：左侧编辑同一个应用的源码，右侧挂载
实时 ETAF 预览。框架从文件发现 example，不内置具体业务 catalog，也不依赖某个
具体应用。

每个 example 遵循同名文件合同：

- `examples/NAME.etaf`：一个 inert 的静态结构 form；
- `examples/NAME.el`：Component、状态、effect 和 root factory（默认命名为
  `etaf-NAME-root`）；
- `examples/NAME.ecss`：可选的 inert `(styles ...)` presentation 规则。

执行 `M-x etaf-playground-open` 打开默认 example。左侧 source 顶部的
`ETAF`、`EL`、`ECSS` 是可点击按钮；`C-c 1/2/3`（也支持
`C-c C-1/C-2/C-3`）分别切换 `.etaf`、`.el`、`.ecss`。在 `.etaf`、`.el` 或
`.ecss` 窗口按 `C-c C-c` 会把当前 source 渲染到右侧预览；默认保存 source
也会刷新。若 root 或 feature 不遵循命名约定，可在 companion 中调用
`etaf-playground-register-example` 注册覆盖。

预览位置使用标准 Emacs `display-buffer` action，由
`etaf-playground-display-action` 配置。默认在右侧使用一半 frame：

```elisp
;; 右侧预览占 frame 的 40%。
(setq etaf-playground-display-action
      '((display-buffer-in-side-window)
        (side . right)
        (window-width . 0.4)))

;; 右侧预览固定为 100 列。
(setq etaf-playground-display-action
      '((display-buffer-in-side-window)
        (side . right)
        (window-width . 100)))

;; 使用独立 frame。
(setq etaf-playground-display-action
      '((display-buffer-pop-up-frame)
        (pop-up-frame-parameters . ((width . 120) (height . 45)))))
```

`etaf-playground-mount-example` 仍作为低层 batch/consumer API 保留。业务
Component、数据库 schema、palette、refs 和 handlers 都应该留在 example companion
中；Playground 只提供 source/preview 会话、读文件、标准 `display-buffer` 展示与
生命周期。

Research Shelf 本身还没有复杂到需要 feature 目录，所以完整的可执行 companion
集中在一个 `.el` 文件里，用注释区分 DATA / THEME / STATE / VIEW / ROOT；只有
Playground 需要发现的入口文件保持同名：

```text
examples/research-shelf.etaf  # inert 结构 source
examples/research-shelf.ecss  # inert 样式 source
examples/research-shelf.el    # DATA / THEME / STATE / VIEW / ROOT 分区
```

该 companion 注册了 `:reload-on-refresh t`；保存 `.el`、`.etaf` 或 `.ecss` 后刷新
source，会在下一次 mount 前重新加载完整 consumer。

验证命令：`make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
性能门禁：`make perf`（1413×62 viewport 的 warm 选行/主题延迟）。

仓库中的 Research Shelf 只是上述通用工作区的一个 consumer。它默认安装确定性的
256 条 SQLite fixture，每页显示 12 条；测试或压测时可以绑定
`etaf-research-shelf-fixture-size` 和 `etaf-research-shelf-page-size` 调整规模，
界面中激活 `Rows N ✎` 可以输入 1–100。
