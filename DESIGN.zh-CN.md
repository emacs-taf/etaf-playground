# 设计

## 来源与状态

- 状态：active
- 更新日期：2026-08-22
- 主产品面：`examples/research-shelf.etaf` + `examples/research-shelf.el`
- HTML 视觉基线：`design/research-shelf.html`
- 已审查：ETAF View/Component/Data API、`etaf-ui` 的公开组件，以及
  `etaf-sqlite` 的 typed source 合同。

## 产品定位

Research Shelf 是一个真正有用的本地研究/阅读架：SQLite 保存书籍、论文、
文章和笔记，用户可以筛选、分页、选择一条记录、更新进度、完成、收藏和归档。
它不是把 API 名称堆成控制台，而是用一个连贯 workflow 验证 ETAF 的组合能力。

## 结构与分层

- Shell：标题/副标题/主题切换 → 三列 workspace → 持久化状态栏。
- 三列 workspace：筛选栏 / SQLite reading list / selected-item detail inspector。
- `.etaf`：只保存经过白名单校验的静态结构和文案（section、filter、label）。
- 同名 `.el`：消费 `.etaf`，组合公开 UI Components，创建 SQLite schema、Data
  Controller、refs、事件处理和生命周期清理。
- 现有可复用组件：`button`、`checkbox`、`label`、`panel`、`data-grid`、
  `pagination`；应用只负责把它们组合成产品，不复制一套 UI kit。

## Playground 框架边界（必须长期遵守）

`etaf-playground.el` 是通用 pair playground 框架，不是业务应用模块。
`etaf-playground-catalog.el` 是独立、可替换的部署目录；业务 pair 的名字、refs
和验证元数据放在 catalog，不写进 loader 实现。

框架只负责：

- pair 注册语义和 catalog 读取；
- `.etaf` 的惰性、inert、白名单读取；
- 按同名 pair 加载 companion；
- mount、reset、close，以及测试/GUI 入口。

框架绝不负责：业务 Component、数据库包或表结构、palette、业务 state、
handlers、resources 或应用 refs。它不能 `require etaf-sqlite`，也不能把业务
组件实现塞进 loader/helper。未来新增例子时，只增加一个同名 `.etaf`/`.el` pair
和 catalog entry，不改变框架语义。

组合和复用是默认设计：优先复用 ETAF/`etaf-ui` 的公开契约，优先拆出清晰的
Component 边界，避免新增 helper 层或抽象泄漏。

## 视觉语言

- 气质：editorial、专注、温暖、安静而聪明；避免通用 admin dashboard、KPI
  墙、假图表、彩虹渐变和装饰性噪声。
- 色彩：ink `#172033`、paper `#F7F3EA`、cobalt `#3657D6`、mint `#3E9B8F`、
  coral `#D86B5D`、amber `#C58A3A`、muted `#6D7482`。
- 节奏：1 格外部节奏、2 格 panel padding、1 格 grid gap，控件保持 intrinsic
  宽度；`grid` 负责页面骨架，`flex` 负责 toolbar/action group。
- 状态：文字和 Unicode 同时表达状态：`⌕`、`★`、`✓`、`◷`、`↗`、`⚠`、`·`。
- 动效：状态立即可见，不依赖 timer animation，默认支持 reduced motion。

## 交互合同

- 筛选：All、In progress、Unread、Finished、Starred。
- 列表：DataGrid 行单选，重复点击可以重新选择；分页按钮在边界处 disabled。
- 详情：`+ 10%`、`✓ Finish`、`☆/★ Star`、`Archive`；完成或 100% 时正确禁用。
- 存储：成功显示 `✓ Saved locally`，失败保留当前可用内容并提供 Reload。
- 主题：Light/Dark 由 checkbox 控制；文字、对比度和布局都应保持可读。
- 键盘：Tab 顺序为筛选 → 行 → 详情动作 → 分页，RET 使用同一组公开 refs。

## 响应式与验证

- Wide/fullscreen 使用 rail / list / detail 三列 grid。
- Compact 时筛选栏收为顶部工具行，detail 位于 list 后面；不使用固定宽度撑坏
  viewport，所有操作控件仍保持独立 hover/focus 语义。
- 用 SQLite 临时文件测试 mount/remount、筛选、分页、重复选行、mutation、错误
  状态和 cleanup；GUI 用干净 fullscreen 单窗口截图验证真实布局。
- 目标：一次 Data mutation 对应一次 Runtime generation/publication；warm 交互
  维持现有 100ms p50 预算。

## 待 review

- [ ] 用户可调整产品命名或 palette；pair 边界、组合/复用原则和公开交互合同不变。
