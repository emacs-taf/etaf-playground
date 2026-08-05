# 设计规范

## 事实来源
- 状态：生效中
- 最近更新：2026-08-05
- 主要产品界面：`etaf-playground-open`、`etaf-playground-open-ui` 与交互式应用 `etaf-playground-open-showcase`。
- 已审阅证据：`etaf-playground.el`、`tests/etaf-playground-tests.el`、中英文 README、当前 Showcase 的真实 GUI 渲染，以及 `../emacs-box/examples/playground/flex-reference.ebox` 的全屏 GUI 渲染。

## 品牌
- 气质：精确、克制、现代、技术感强，并且明显经过设计，而不是通用框架默认外观。
- 可信信号：精确对齐、清晰对比度、更新时稳定的几何结构、一致的语义颜色，以及能够真实演示 ETAF 公共模型的例子。
- 避免：未加样式的默认 Emacs 文本、过度饱和的仪表盘颜色、浅色背景上的低对比文字、装饰噪音、无意义的大面积留白，以及与普通正文无法区分的控件。

## 产品目标
- 目标：通过精致、可运行的应用体现 ETAF 的能力；用可见结构讲清 View、Component、Context、Data、Grid、保留状态与事件；所有例子只使用公共 API。
- 非目标：模仿浏览器、使用位图装饰、另建样式框架、加入仅供示例使用的隐藏渲染路径，或假装当前较小的 `etaf-ui` 目录已经功能完整。
- 成功信号：首屏具有明确的应用结构；导航、数据和主题更新保持层级与几何稳定；截图中没有裁切、续行标记、意外换行或低对比文字。

## 用户与任务
- 主要用户：ETAF 应用作者、Ebox/ETAF 维护者，以及评估新架构是否可用的人。
- 用户任务：快速理解框架、复制公共 API 模式、检查真实交互流程，并确认更新后视觉结构稳定。
- 主要环境：GUI Emacs 单应用缓冲区、全屏演示，以及批处理/ERT 验证。

## 信息架构
- 主导航：固定的横向命令条，包含 Overview、Work items 与 Theme。
- 核心界面：Overview 仪表盘、交互式 Work items 表格、Theme and semantics 色彩页、紧凑的核心计数器例子，以及可选的 `etaf-ui` 组件目录例子。
- 内容层级：品牌应用标题、固定导航、页面标题与说明、主要卡片或表格、上下文操作区，以及安静的状态栏。

## 设计原则
- 原则一：通过可见分组教学；每项能力都放在有标题、有边界的区域中，而不是混成一串文本。
- 原则二：沿用 Flex 参考示例的暖色、克制配色与一像素边框，不依赖阴影或浏览器专有视觉效果。
- 原则三：几何正确性就是功能正确性；viewport owner 必须包含自身边框，子区域必须适配 owner 的内容盒，更新不得引入换行或截断标记。
- 取舍：优先采用适合桌面 Emacs 的紧凑构图，而不是过量留白；内部响应式容器省略宽度，让 Ebox Flex 分配和换行，避免脆弱的多层 viewport 算术。

## 视觉语言
- 颜色：暖白画布 `#F8F5EE`；纸张 `#FFFDF8`；正文 `#252A2E`；弱化文字 `#66706A`；激活陶土色 `#B84F35`；淡陶土色 `#F1D4C9`；鼠尾草绿 `#DCEBDD`；蓝色 `#D9EAF2`；紫色 `#E7E2F1`；暗色模式使用深中性色表面和同一组语义色的亮色版本。
- 字体：沿用 Emacs 配置的等宽字体；粗体只用于标题、标签、关键数值和激活控件。
- 间距：纵向以一行作为节奏；横向间距 12–16px；区块内边距 16–24px；卡片与表格边缘对齐。
- 形状与层级：方正的文本原生表面、一像素边框，不模拟圆角或阴影。
- 动效：状态直接发布，并在 redisplay 后保持稳定；不使用装饰动画。
- 图像与图标：只使用文字与克制的语义符号，不使用 logo、emoji 装饰或位图外框。

## 组件
- 复用能力：ETAF 核心 Hosts、保留式 Components、Grid、Context 主题值、Data Controller 与公共事件分发。
- 新增或调整：Showcase 区块标题、指标卡、导航项、任务行、操作按钮、色板、紧凑状态栏，以及核心/UI 例子的精致外壳。
- 状态：激活导航、选中任务、启用/禁用操作、亮色/暗色主题、success/review/open、loading、empty 与 error。
- 所有权：色彩 token 位于 `etaf-playground--showcase-palette`；各 helper 拥有自己的展示表面；ETAF/Ebox 继续拥有布局与渲染。

## 可访问性
- 目标：高对比、可用键盘操作的 Emacs UI，并保留明确的语义 role 与 ref。
- 键盘与焦点：所有可操作表面保留 `:role 'button`、`:tab-index 0`、稳定 ref，以及可见的激活/选中样式。
- 对比度：所有着色表面都有明确前景色；弱化文字在画布与纸张上都可读；激活控件同时使用颜色、边框或背景变化。
- 语义：框架支持时保留 label、role、ref 与 `aria-label`。
- 动效：不依赖动画，普通 redisplay 即可使用。

## 响应式行为
- 支持范围：约 900px 宽的 GUI Emacs 窗口到全屏桌面宽度；验证时还使用 777px 可用宽度作为更严格下限。
- 布局适配：宿主测量窗口正文，并在右侧预留一个字符单元；最外层 shell 拥有 viewport 宽度；直接的 header/main/status 区域在其中 stretch；嵌套响应式容器省略宽度，由 Ebox Flex 分配或换行。
- 触摸/悬停：不适用；键盘与鼠标 press 共用公共事件模型。

## 交互状态
- Loading：有标签、有边界，并显示明确状态。
- Empty：安静的解释区域；可用时给出下一步操作。
- Error：高对比 danger 区域；错误保持可见，不静默回退。
- Success：鼠尾草绿强调色与明确反馈文本。
- Disabled：弱化前景色，并移除回调与 tab stop。
- 离线/慢网络：当前不适用，因为示例使用同步内存数据源。

## 内容语气
- 风格：直接、技术化、简洁、自解释。
- 术语：统一使用 ETAF 词汇：View、Component、Host、Context、Data Controller、Runtime、event 与 public API。
- 文案规则：说清正在演示的能力和操作后的可见结果，避免宣传式填充文字。

## 实现约束
- 技术边界：Emacs 29.1+、ETAF 公共 View/Component API，以及 Ebox 公共布局/样式属性。
- Token：复用 palette helper 与语义 token key；不新建平行主题或 CSS 层。
- 性能：交互保持同步且有界；视觉改进不得增加隐藏的全树工作或除现有 viewport sync 外的新 timer。
- 兼容性：`etaf-playground` 必须独立于 `ebox-playground`，不得调用 `ebox--*` 私有 API。
- 验证：`make check` 通过；GUI 截图只显示一个目标缓冲区窗口；动态检查覆盖导航、选择、新增、主题切换与返回 Overview；不接受可见截断/续行标记或意外换行。

## 待解决问题
- [ ] 扩展官方 `etaf-ui` 目录后，才能把目录示例表述为完成迁移的组件画廊；维护者；阻止错误的功能对等声明。
