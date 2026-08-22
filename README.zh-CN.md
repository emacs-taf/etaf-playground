# ETAF Playground

Playground 只公开一个标准产品示例：
`examples/research-shelf.etaf` 与 `examples/research-shelf.el` 配对。

`.etaf` 是惰性、inert、经过白名单验证的静态结构数据；同名 companion 负责
Component、状态、主题、SQLite、事件与生命周期。`etaf-playground.el` 是通用
pair playground 框架，只负责注册、白名单读取、加载、mount/reset/close 和验证
入口；`etaf-playground-catalog.el` 是可替换的部署目录。业务 Component、数据库
schema、palette、refs 与 handlers 不能泄漏进框架。
默认原则是组合和复用公开 ETAF/`etaf-ui` 契约，而不是再造一套组件或 helper 抽象。

验证命令：`make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
性能门禁：`make perf`（1413×62 viewport 的 warm 选行/主题延迟）。

示例默认安装确定性的 256 条 SQLite fixture，每页显示 12 条。测试或压测时可以
绑定 `etaf-research-shelf-fixture-size` 和 `etaf-research-shelf-page-size` 调整规模；
界面中激活 `Rows N ✎` 可以输入 1–100。Workspace 使用同一套 wrapping Flex：
宽屏三栏，中屏 detail 换行，窄屏按文档顺序变为纵向布局。
