# 设计

## 来源与状态

- 状态：active
- 更新日期：2026-08-23
- 主产品面：通用 `etaf-playground.el` 工作区，以及
  `examples/research-shelf.etaf` / `.el` / `.ecss` consumer 三件套
- HTML 视觉基线：`design/research-shelf.html`
- 已审查：ETAF View/Component/Data API、`etaf-ui` 的公开组件，以及
  `etaf-sqlite` 的 typed source 合同。

## 产品定位

Research Shelf 是一个真正有用的本地研究/阅读架：SQLite 保存书籍、论文、
文章和笔记，用户可以筛选、分页、选择一条记录、更新进度、完成、收藏和归档。
它不是把 API 名称堆成控制台，而是用一个连贯 workflow 验证 ETAF 的组合能力。
Playground 默认安装确定性的 256 条 fixture、每页 12 条，用于真实验证分页、DataGrid
增量更新和 SQLite 查询压力；fixture 数量和 page size 都可以配置。

## 结构与分层

- Shell：标题/副标题/主题切换 → 三列 workspace → 持久化状态栏。
- 三列 workspace：筛选栏 / SQLite reading list / selected-item detail inspector。
- `.etaf`：只保存经过 inert 校验的静态结构和文案（section、filter、label）。
- `.ecss`：可选的 inert `(styles ...)` 规则，由 companion 消费并应用到 ETAF
  Component style scope。
- 同名 `.el`：消费 `.etaf/.ecss`，组合公开 UI Components，创建 SQLite schema、Data
  Controller、refs、事件处理和生命周期清理。
- 现有可复用组件：`button`、`checkbox`、`label`、`panel`、`data-grid`、
  `pagination`；应用只负责把它们组合成产品，不复制一套 UI kit。

## Playground 框架边界（必须长期遵守）

`etaf-playground.el` 是通用的 source/preview 工作区，不是业务应用模块。它从同名
`.etaf`/`.el` 文件发现应用，并把可选的 `.ecss` 作为第三个 source tab；左侧是
源码会话，右侧是 ETAF 预览。

框架只负责：

- 惰性、inert 的 `.etaf`/`.ecss` 读取和 companion 注册覆盖；
- `.etaf`、`.el`、`.ecss` source buffer 的 tab 切换；
- 左右窗口布局、刷新、reset、close，以及 ETAF Runtime 生命周期。

框架绝不负责：业务 Component、数据库包或表结构、palette、业务 state、
handlers、resources 或应用 refs。它不能 `require etaf-sqlite`，也不能把业务
组件实现塞进 loader/helper。未来新增例子时，只增加一个同名 `.etaf`/`.el` pair，
必要时再加 `.ecss`，不改变框架语义。

组合和复用是默认设计：优先复用 ETAF/`etaf-ui` 的公开契约，优先拆出清晰的
Component 边界，避免新增 helper 层或抽象泄漏。

## Research Shelf 的 companion 边界

Research Shelf 目前足够小，完整的可执行 companion 放在一个文件中，用注释明确
业务边界：

```text
examples/research-shelf.etaf                inert 结构 source
examples/research-shelf.ecss                inert 样式 source
examples/research-shelf.el                  DATA / THEME / STATE / VIEW / ROOT
```

`.el` 文件是唯一的 Playground 注册点和 palette owner；它的 THEME 区域可以
通过可选的 `etaf-theme-tp` adapter 把 TP 的亮/暗 pair 转成 ETAF 语义 Theme plist，
其余应用代码不直接调用 TP，也不嵌入 renderer palette 名称。VIEW 区域在 shell
Component 内创建
Data Controller，因此 ETAF 会自动把它的 effect Scope 归 Component 所有，并在
Component 销毁时释放 SQLite source。详情和筛选 Component 通过 Context 消费依赖、
dispatch 命名 Action，不直接访问 SQLite，也不重复实现 selection 匹配。`.etaf`
负责静态结构，`.ecss` 负责 token。未来如果产品复杂度真的增长，再把这些注释区段
迁移到目录模块，而不改变 Playground 的同名三文件入口。

实现约束补充：有意热加载统一通过 `etaf-component-redefine-run`，应用代码不绑定
ETAF 私有 registry 变量；Component setup 中创建的 Controller 自动归当前 Scope
所有，选中项使用带明确 `:item-key` 的 `etaf-data-selected-item`。

## 视觉语言

- 气质：editorial、专注、温暖、安静而聪明；避免通用 admin dashboard、KPI
  墙、假图表、彩虹渐变和装饰性噪声。
- 色彩：ink `#172033`、paper `#F7F3EA`、cobalt `#3657D6`、mint `#3E9B8F`、
  coral `#D86B5D`、amber `#C58A3A`、muted `#6D7482`。
- 节奏：1 格外部节奏、2 格 panel padding、1 格 workspace gap，控件保持
  intrinsic 宽度；需要分配剩余空间或换行时统一使用 `flex`。
- 状态：文字和 Unicode 同时表达状态：`⌕`、`★`、`✓`、`◷`、`↗`、`⚠`、`·`。
- 动效：状态立即可见，不依赖 timer animation，默认支持 reduced motion。

## 交互合同

- 筛选：All、In progress、Unread、Finished、Starred。
- 列表：DataGrid 行单选，重复点击可以重新选择；分页按钮在边界处 disabled。
- 每页行数：激活 `Rows N ✎` 后使用 Emacs 原生 minibuffer 输入 1–100 的整数，
  应用后回到第一页。
- 详情：`+ 10%`、`✓ Finish`、`☆/★ Star`、`Archive`；完成或 100% 时正确禁用。
- 存储：成功显示 `✓ Saved locally`，失败保留当前可用内容并提供 Reload。
- 主题：Light/Dark 由 checkbox 控制；文字、对比度和布局都应保持可读。
- 键盘：Tab 顺序为筛选 → 行 → 详情动作 → 分页，RET 使用同一组公开 refs。

## 响应式与验证

- Wide/fullscreen：rail / list / detail 位于同一条 Flex line，呈现三栏。
- Medium：rail 与 list 保持同排，detail 自动换到下一行。
- Narrow：同一组三个 Component 按文档顺序自动变为纵向流。
- Shell 只使用一套带 basis/grow 权重的 wrapping Flex，不读取窗口宽度、不维护
  breakpoint 状态；`row` 只负责紧凑 intrinsic 控件，所有操作控件仍保持独立
  hover/focus 语义。
- 用 inert reader、source tab/session、未保存 source refresh 和 SQLite 临时文件
  测试 mount/remount、筛选、分页、重复选行、mutation、错误状态和 cleanup；GUI
  用干净 fullscreen 截图验证真实布局。
- 目标：一次 Data mutation 对应一次 Runtime generation/publication。当前有效的
  延迟 lane 在固定 1413×62 几何下执行 5 次未计时 warmup 与 30 个计时 sample，
  每个场景的 p95 和 max 均须不超过 50ms。已接受的 105ms p50 是历史设计上下文，
  不是当前 evaluator gate；其正式处置仍由 M0b1 的 `DOC-PERF-001` 负责。
- 压测入口：`etaf-research-shelf-fixture-size` 默认 256，
  `etaf-research-shelf-page-size` 默认 12；已有本地记录保留，不足部分使用新 ID
  补齐 fixture。

## 性能 evidence lanes

延迟 lane、追踪 lane 与 GUI lane 共享同一组仓库、环境、场景、fixture 和 build identity，
但保持为三种独立测量。延迟 lane 负责无 instrumentation 的 5/30、p95/max 50ms
门禁；追踪 lane 负责一次代表性 instrumented invocation 的 cost class、work counters、
turns、allocation 与 GC；GUI lane 负责真实 Emacs action sequence、截图、录像与
temporal-review verdict。Batch verifier duration 不是 GUI first paint；从 action-start
到 forced redisplay completion 的 first-paint 计时仍是独立 future gate，也是 M0a
明确记录的 observed gap。任何一条 lane 都不能替另一条 lane 宣称通过。

## 待 review

- [ ] 用户可调整产品命名或 palette；pair 边界、组合/复用原则和公开交互合同不变。
