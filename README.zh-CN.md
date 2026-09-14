# ETAF Playground

ETAF Playground 是通用的应用构建工作区：左侧编辑同一个应用的源码，右侧挂载
实时 ETAF 预览。框架从文件发现 example，不内置具体业务 catalog，也不依赖某个
具体应用。

每个 example 遵循同名文件合同：

- `examples/NAME.etaf`：一个 inert 的静态结构 form；
- `examples/NAME.el`：Component、状态、effect 和 root factory（默认命名为
  `etaf-NAME-root`）；
- `examples/NAME.ecss`：可选的 inert `((SELECTOR PROPERTY VALUE ...) ...)` presentation 规则。

执行 `M-x etaf-playground-open` 打开默认 example。左侧 source 顶部的
`ETAF`、`EL`、`ECSS` 是可点击按钮；`C-c 1/2/3`（也支持
`C-c C-1/C-2/C-3`）分别切换 `.etaf`、`.el`、`.ecss`。在 `.etaf`、`.el` 或
`.ecss` 窗口按 `C-c C-c` 会把当前 source 渲染到右侧预览；默认保存 source
也会刷新。若 root 或 feature 不遵循命名约定，可在 companion 中调用
`etaf-playground-register-example` 注册覆盖。

ETAF Playground 0.2.2 声明 ECSS 0.1.0、ETAF 0.2.1、ETAF UI 0.1.0 与 ETAF SQLite
0.1.0，保证内置 Research Shelf companion 的安装依赖闭包完整。

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

直接打开 inert `.etaf` 或 `.ecss` source 时只加载轻量编辑 mode；刷新或 mount
preview 时才加载 ETAF/Ebox/TP runtime。运行 preview 需要 TP 1.0.1 或更高版本，
以保证 `tp-transaction.el` 与 Host final-accept contract 已安装。

该 companion 注册了 `:reload-on-refresh t`；保存 `.el`、`.etaf` 或 `.ecss` 后刷新
source，会在下一次 mount 前重新加载完整 consumer。

## 可重复执行的 Emacs 31.1 GUI 实测

当前 GUI 验收使用用户已经运行的图形 Emacs server：通过 `emacsclient`
在明确命名的 buffer 中渲染，保留当前应用焦点，只截取已有窗口并检查。
保留用户字体、编码设置和正常 GC 策略；连接失败时不自动启动 daemon 或另建 frame。

本仓库及 sibling 依赖已在 Emacs 的 load-path 中时：

```sh
emacsclient --eval '(progn (require (quote task-workbench)) (wb-open "*Workbench review*"))'
```

维护中的例子位于 `examples/task-workbench.el`；require 前需将 examples
目录加入 load-path。自动交互验证可在 `emacs-gui-verifier` 引擎及适配器
依赖已经可用后，加载 `scripts/task-workbench-gui-scenarios.el`，在已有 frame 执行：

```elisp
(task-workbench-gui-prepare)
(run-at-time 0.05 nil #'task-workbench-gui-run "/absolute/fresh/evidence-directory")
```

引擎将窗口截图、`manifest.jsonl` 和原子写入的 `result.json` 保存到证据目录。
结果通过只表示动作断言通过，外观仍需检查实际截图。适配器使用公开的 Host、
selector 查询和已显示的值；被视口裁出的数量在检查点元数据中记录为 null，
增删和筛选步骤仍严格要求显示预期数量。适配器要求新的专用验收 buffer，并保留当前
渲染后端。准备阶段也保留应用焦点；显式调用 `(task-workbench-gui-prepare t)`
才会切到前台。后台的 Emacs 本地动作可以验证功能，其耗时不能证明前台显示延迟。
只有显式设置 `EBOX_NATIVE_REFLOW_MODULE_PATH` 时，才要求加载该路径下的兼容
native 模块。适配器不启动 server。需检查 mounted Runtime、动作断言和实际截图；
截图本身不能证明延迟上界或无闪烁。现有 server 的截图与录屏细节见
[ETAF GUI 验证指南（英文）](https://gitea.gklazycat.heiyu.space/geekinney/etaf/src/branch/main/docs/manual.md#gui-verification-tools)。

以下命令是保留的 **legacy 隔离环境工具**，只用于明确选择独立测试 Emacs 的
场景，不是当前默认的 existing-server 流程：

```sh
make gui-doctor
make gui-research
make gui-flex
make gui-grid
# 或在独立测试实例中按顺序采集四个场景：
make gui-all
```

可复用的执行引擎与进程 runner 位于 `../etaf/scripts/`，只理解 Scenario、Action、
Context、checkpoint、录屏和 evidence 合同。`scripts/playground-gui-scenarios.el` 只是
薄适配层：Research Shelf 提供应用动作，Flex 与 Grid 只是同一个 Ebox reference
scenario factory 的两个输入。增加新应用时不会复制第二套 daemon/录屏/checkpoint
实现。

每个场景都会创建唯一命名 daemon，关闭 native-comp JIT，显式加载 sibling 仓库，
创建单一 GUI frame，由外层 shell 激活 Emacs，通过保留 PTY 的 macOS recorder 录屏，
依次执行 mount/resize/scroll/interaction checkpoint，生成 screenshot 与 manifest，最后
清理自己创建的全部进程。Flex 与 Grid 直接读取 `ebox-playground` 当前工作文件，确保
门禁验证的就是用户正在测试的代码；runner 绝不写入、暂存、恢复或以其他方式修改
这两个 fixture。

新采集有意保持 `INCOMPLETE`，直到人或 agent 检查 `report.md`、
`contact-sheet.png` 和报告选出的首尾图。完成时序审查后，对同一个 run directory
执行：

```sh
scripts/run-gui-verification.sh review /private/tmp/etaf-playground-gui.XXXXXX
```

对于这套 legacy 录屏包，只有 `VERDICT=PASS` 才证明其审查完成；这个 verdict
不是另一条 existing-server 流程的必要条件。assertion 失败、黑帧、录屏缺失、错误 buffer、
split window、陈旧 frame 或没有完成时序审查都会保持 fail-closed。

验证命令：`make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
批处理回归：`make perf`（Research Shelf 的 1413×62 viewport，选行/主题延迟）。

工作台另有快速批处理负载。先执行 `make check` 编译当前 checkout 及依赖：

```sh
ETAF_WORKBENCH_BENCHMARK_OUTPUT=/tmp/workbench-before.json make perf-workbench
# 修改并重新编译后：
ETAF_WORKBENCH_BENCHMARK_OUTPUT=/tmp/workbench-after.json make perf-workbench
python3 scripts/compare-workbench-performance.py /tmp/workbench-before.json /tmp/workbench-after.json
```

行状态切换、主题切换和新增按钮定位各自使用独立的 100 条任务、每页 10 条应用，
固定执行 5 次预热和 30 次采样，每次都在计时区间外验证发布结果。报告保留原始
样本、环境和源码摘要；对比命令重新计算 p95/max，拒绝环境不匹配或不完整的证据，
增幅超过 2 ms 或超过既有 50 ms 门槛均返回失败。比较应用版本时保持测量程序不变。
这是批处理的分发至发布耗时，完整 GUI 流程和前台延迟仍需分别验收。未指定输出变量
时，命令打印自动创建的临时报告路径。应用消息另存临时日志，终端显示耗时、结论和
报告／日志路径。

定位高开销操作使用 `make profile-workbench SCENARIO=row-toggle`，也支持
`theme-toggle`、`focus-add`。同一套带结果断言的负载分别创建两个实例：先记录公共
提供方阶段，再独立做 CPU 采样。每轮预热 5 次，默认诊断 10 次动作。终端只显示
可重叠的阶段平均耗时，以及每个 CPU 样本最近的具名包函数。后者互不重复归类；
匿名或原始函数帧归入最近的具名调用者，只有 GC／宿主运行时的样本可能没有归属。
JSON 保留逐次操作、脱离闭包状态的采样栈、
函数自身／含子调用的采样权重、源码位置、加载版本、工作区改动和源码摘要。
用 `ETAF_WORKBENCH_PROFILE_OUTPUT` 指定报告位置，用
`ETAF_WORKBENCH_PROFILE_SAMPLES=1..100` 设置动作数。
默认保留最多 256 层调用栈，可用 `ETAF_WORKBENCH_PROFILE_STACK_DEPTH=16..1024`
调整。报告标记达到深度上限的栈，并显示其采样权重。此类栈可能遗漏外层调用者，
导致含子调用的排名低估这些函数；据此定位架构层成本前，应提高深度重新采样。
结合保留的调用栈与自身／含子调用计数区分自身工作和下游工作，不能把含子调用总量
当作该函数本身的开销。
函数采样是统计证据，不是调用次数或精确函数耗时；匿名闭包可能无法命名，极短
动作可能没有 CPU 样本并返回诊断失败。沿热点调用路径检查职责归属及重复工作，
修复后使用独立的**无采样** `perf-workbench` 对照验收。这些带观测开销的运行
不能充当延迟或 GUI 验收通过的证据。

当前 GUI 验收还要求三组独立的前台实测，每项操作从回调开始到强制 redisplay
返回的 p95 和 max 均不超过 50ms；该门禁尚未通过。使用
[ETAF GUI 测量指南（英文）](https://gitea.gklazycat.heiyu.space/geekinney/etaf/src/branch/main/docs/manual.md#measuring-an-existing-gui-action)
中的测量入口，保留预热、GC 记录和全部样本。
redisplay 返回不能证明操作系统已经呈现画面，批处理结果也不能替代 GUI 门禁。

仓库中的 Research Shelf 只是上述通用工作区的一个 consumer。它默认安装确定性的
256 条 SQLite fixture，每页显示 12 条；测试或压测时可以绑定
`etaf-research-shelf-fixture-size` 和 `etaf-research-shelf-page-size` 调整规模，
界面中激活 `Rows N ✎` 可以输入 1–100。

## 开发

克隆后运行 `make setup-hooks`。提交变更前运行 `make check`；`make structure-check` 用于快速检查目录、命名和引用。

`make check` 运行规范检查、编译及 [tests/acceptance.json](tests/acceptance.json) 中的公共验收场景。`make test` 运行同一套公共 API 测试。清单涵盖全部维护的 Lisp 测试。GUI 与性能验收使用独立入口。
