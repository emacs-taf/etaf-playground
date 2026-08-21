# 设计

## 来源与状态

- 状态：唯一 reviewed pair 的 active draft
- 更新日期：2026-08-20
- 主产品面：`examples/operations-console.etaf` + `examples/operations-console.el`
- 视觉参考：`design/operations-console.html`
- 已审查证据：pair loader/manifest、`etaf-ui.el`、Ebox viewport 合同及当前 GUI/性能证据。

## 品牌

- 气质：安静的操作控制台；准确、温暖、克制地体现技术感。
- 信任信号：状态 chip、更新时间、明确计数、清晰的成功/错误反馈。
- 避免：普通玩具 dashboard、彩虹渐变、无语义状态的装饰控件和杂乱控制区。

## 产品目标

- 用一个好看的 app 同时展示 Component、组合、响应式、Context/Theme、Behavior、事件/Action、Data、Resource、错误边界、焦点和生命周期。
- 不扩展第二个 Playground 场景，不伪装成完整生产分析产品，不用假动画掩盖框架问题。
- HTML 原型和 ETAF 实现保持同一层级、状态文字、交互结果和 compact/fullscreen 几何。

## 信息架构

- Shell：品牌/header → 导航 tabs → page surface → 持久 status footer。
- Overview：hero/status、KPI 卡片、活动/控制 workspace、能力卡片和事件时间线。
- Data：选择摘要、可交互 DataGrid、selection detail。
- Resource：资源状态、reload/fail-next、boundary 结果和 cleanup 计数。
- 层级：先显示页面标题和状态，再显示主操作，最后显示诊断/细节。

## 设计原则

1. 一个视觉层级：每个控件属于有名字的 surface，每个 surface 都有可见状态。
2. 状态优先于装饰：theme、loading、error、selected、disabled、success 都有文字表达。
3. 几何稳定：compact 下控件保持单行，页面只替换 page surface。
4. API 真实：HTML 可以用普通 HTML/JS，但 ETAF 只用公开 ETAF/ETAF-UI API。

## 视觉语言

- 色彩：墨蓝 `#142235`、纸张 `#F6F1E8`、灰蓝 `#526174`、青绿 `#2E8B83`、珊瑚 `#E26D5A`、琥珀 `#D99A3D`、成功绿 `#3E9B72`。
- 字体：易读 sans body，紧凑 monospace 指标/标签，粗体页面标题。
- 节奏：一行外部节奏、双列 workspace、固定 gap、shell 全宽，卡片有明确内边距。
- 形状：细深色边框、克制 elevation；ETAF 不依赖浮层。
- 动效：不以动画为正确性前提，状态变化即时且支持 reduced motion。
- 图形：只用文字标记和 Unicode 状态符号，不依赖外部资源。

## 组件

- 复用公开 `button`、`checkbox`、`label`、`panel`、`data-grid`。
- companion 组件：`operations-console-shell`、`hero-status`、`metric-strip`、`activity-card`、`capability-card`、`timeline`、`data-page`、`resource-page`。
- 状态：active/inactive nav、light/dark theme、selected/unselected row、Behavior on/off、resource ready/loading/error、boundary handled、compact/fullscreen。
- 所有权：`.etaf` 只放静态 composition 和 section 名称；`.el` 持有 token、props、refs、资源、handlers 和 state。

## 无障碍

- 目标：键盘完整、高对比文字，使用公开组件提供语义 role。
- Tab/Shift-Tab 遍历 nav/action/data rows；RET 派发 focused ref；移除目标时清焦点。
- 每个状态都有文字反馈，颜色不是唯一信号；不依赖 hover-only 行为。
- Ebox Theme 承载继承的 Ebox 默认属性；应用 palette 仍由 companion 查询，
  Renderer 会在进入 Ebox 几何层前过滤未知 token 名。

## 响应式

- 支持 compact 900–940px body 和 fullscreen desktop GUI。
- metric 尽量一行展示，workspace 从双列退化为上下堆叠，控件保持 intrinsic 单行宽度。
- 需要分配剩余宽度的行使用 `flex`，固定 intrinsic 控件组才使用 `row`；导航
  控件组使用 max-content，确保每个 hover/active 区域都是独立控件。
- mouse-1 和键盘激活使用同一组公开 refs。

## 交互状态

- Loading：Resource 显示 `Loading…`，shell 几何不移动。
- Empty：DataGrid 明确显示 empty，选择控件仍可用。
- Error：reload 可故意失败一次，Boundary 显示 handled error 且仍可恢复。
- Success：action/status 和 timestamp 可见更新。
- Disabled：不可用操作暴露 disabled 语义，不静默吞输入。

## 内容语气

- 简洁、操作化、解释性；标签明确指出正在展示的框架能力。
- 统一使用 `Component`、`Context`、`Theme`、`Behavior`、`Action`、`Data`、`Resource`、`Boundary`。
- 优先“动词 + 结果”（如 `Reload resource`、`Handled: …`、`Selected Beacon`）。

## 实现约束

- 使用 `.etaf`/`.el` 的公开 ETAF View DSL，由 Ebox 渲染，不引入 HTML/CSS runtime dependency。
- palette/spacing token 在 companion 单处定义并复用，禁止散落临时色值。
- 性能：普通 warm p50 <=100ms，counter/resource p50 <=150ms，每个 warm max <=250ms；每个逻辑动作一次 publication。
- 保留唯一同名 `operations-console` pair、静态安全读取、公开 API boundary、双 mount/unmount cleanup 和 manifest 语义。
- 导航：稳定的 page ref 由 retained router Component 读取；页面 Host 是唯一 semantic Range 锚点，页面切换只替换一个 Range payload，不重建 shell root。
- HTML 是视觉参考；ETAF 需要 compact/fullscreen 截图和动态键鼠 checkpoint 证明布局、宽度、焦点和状态。

## 待 review

- [ ] 用户可在第一版 HTML/ETAF 对照后调整 palette 或页面命名；行为和公开 ref 覆盖保持不变。
