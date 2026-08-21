# ETAF UI paired examples — postmortem / 组件配对示例复盘

## English

### Context

The playground originally mixed a large hand-written Host tree with an
optional catalog entry. That made the primary examples fail to teach the
official Component contract and encouraged example-only button/grid helpers.

### Decision and why

Each runnable example is now a same-basename `examples/<name>.etaf` + `.el`
pair. The `.etaf` file is safe static data and the companion owns state,
controllers, and callbacks through the public pair loader. This preserves the
formal data boundary and makes source/build/mount behavior testable. `etaf-ui`
is a required dependency because the examples are intended to prove the
official Button, Checkbox, Label, Panel, and DataGrid semantics—not a fallback
catalog.

The semantic behavior belongs in `etaf-ui`, not in playground compensation:
disabled controls lose callbacks and tab stops, and interactive DataGrid rows
receive stable refs, roles, and tab indexes. The Showcase layout uses a
vertical growable main region with a bottom status region, so geometry remains
the framework/layout contract rather than a collection of timing hacks.

### Follow-up

Keep pair files small and explicit. Extend the public catalog or core API when
a reusable semantic capability is missing; do not copy a private implementation
into an example.

## 中文

### 背景

旧 playground 把大段手写 Host 树与可选组件目录混在一起，主示例没有真正教授
官方 Component 契约，也容易催生只供示例使用的 button/grid helper。

### 决策与原因

现在每个可运行示例都是同名的 `examples/<name>.etaf` + `.el` 配对。`.etaf`
是安全的静态数据，companion 通过公共 pair loader 持有状态、controller 与
callback。这样保留正式数据边界，并且可以测试 source/build/mount 全流程。
`etaf-ui` 改为必需依赖，因为示例的目的就是证明官方 Button、Checkbox、Label、
Panel、DataGrid 的语义，而不是提供备用目录。

语义行为归 `etaf-ui` 所有，而不是由 playground 补偿：disabled 控件移除
callback 和 tab stop；可交互 DataGrid 行拥有稳定 ref、role 与 tab-index。
Showcase 使用可增长的纵向 main 和底部 status，使几何成为框架/布局契约，而
不是一组 timing hack。

### 后续

保持配对文件小而明确。若缺少可复用语义能力，应扩展公共目录或核心 API；不要
把私有实现复制进示例。
