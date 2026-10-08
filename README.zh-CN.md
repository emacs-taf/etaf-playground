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
也会刷新。若 root 不遵循命名约定，可在 companion 中调用
`etaf-playground-register-example` 注册覆盖。

ETAF Playground 0.2.2 声明 ECSS 0.1.0、ETAF 0.2.1、ETAF UI 0.1.0、ETAF DB
0.1.0 与 ETAF Desktop 0.1.0（SQLite 只由 Research Shelf 使用），保证内置
consumer 的安装依赖闭包完整。

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
preview 时才加载 ETAF/Ebox runtime。

该 companion 注册了 `:reload-on-refresh t`；保存 `.el`、`.etaf` 或 `.ecss` 后刷新
source，会在下一次 mount 前重新加载完整 consumer。

## ETAF Desktop consumer

执行 `(etaf-playground-open "desktop")`，通过通用 Playground 工作区挂载独立的
`etaf-desktop` 应用。该示例包含两个文本窗口，展示应用层拥有的标题栏拖动、调整大小、
z-order、最小化和恢复策略。Playground 只负责 source 发现与生命周期，窗口状态和操作
仍由 `etaf-desktop` 提供。

桌面宿主的实际 GUI 验收使用已经运行的图形 Emacs server；命令不会启动或关闭另一个
Emacs：

```sh
make gui-desktop
scripts/run-desktop-gui-verification.sh run --scenario demo
scripts/run-desktop-gui-verification.sh review /tmp/etaf-desktop-gui.XXXXXX
```

需要固定证据目录时，给 `run-desktop-gui-verification.sh run` 传入
`--run-dir DIRECTORY`。默认选择 `--scenario shell`，`make gui-desktop` 也采用
该场景。它的 26 个检查点使用静态文本应用，检查实际渲染标题栏和调整大小把手的
鼠标事件、工作区、窗口生命周期、应用错误隔离、平铺和设置。设置检查包括紧凑面板、
稳定的背景和行高、通过 minibuffer 编辑间距、值保留、重置及退出时的焦点恢复。

`--scenario demo` 挂载维护中的六应用 Desktop demo：Notes、Tasks、Calculator、
Clock、Chat 和 Monitor。它在 Clock 定时器运行时检查真实应用控件和窗口／工作区
切换，包括最小化和恢复 Clock。所有默认桌面快捷键通过 buffer keymap 进入；
左右与上下分割器通过原生拖动绑定执行分步移动、释放、逆向和边界操作，同时检查
双窗几何、平铺交换和分割比例保留。静态 shell 场景不覆盖这些应用交互；Desktop
验收需运行两个场景。

两个场景都在挂载前于实际目标 buffer 测量普通正文行，保留用户字体和行间距。
检查点拒绝高于该基线的物理行；焦点切换与 Settings 的每个页签还检查未移动窗口
Host 的像素 Y 保持不变。允许较薄的边框行，不提高正文行高上限。

运行器支持 `EMACSCLIENT`，并用 `GUI_TIMEOUT` 限制单次运行时长（默认 180 秒）。
每个全新证据目录会写入 `manifest.jsonl`、`result.json` 和检查点的窗口级 PNG。
通过结果只证明所选场景的功能断言；声明视觉验收前必须逐张检查 PNG。
通过结果和外部超时限制都不证明交互延迟达标。

## 可重复执行的 Emacs 31.1 GUI 实测

当前 GUI 验收使用用户已经运行的图形 Emacs server：通过 `emacsclient`
在明确命名的 buffer 中渲染，保留当前应用焦点，只截取已有窗口并检查。
保留用户字体、编码设置和正常 GC 策略；连接失败时不自动启动 daemon 或另建 frame。

本仓库及 sibling 依赖已在 Emacs 的 load-path 中时，可用 legacy 隔离运行器跑其余场景：

```sh
scripts/run-gui-verification.sh research-shelf
```

引擎将窗口截图、`manifest.jsonl` 和原子写入的 `result.json` 保存到证据目录。
结果通过只表示动作断言通过，外观仍需检查实际截图。适配器使用公开的 Host、
selector 查询和已显示的值；被视口裁出的数量在检查点元数据中记录为 null，
各步骤仍严格要求显示预期数量。适配器要求新的专用验收 buffer，并保留当前
渲染后端。后台的 Emacs 本地动作可以验证功能，其耗时不能证明前台显示延迟。
只有显式设置 `EBOX_NATIVE_REFLOW_MODULE_PATH` 时，才要求加载该路径下的兼容
native 模块。适配器不启动 server。需检查 mounted Runtime、动作断言和实际截图；
截图本身不能证明延迟上界或无闪烁。现有 server 的截图与录屏细节见
[ETAF GUI 验证指南（英文）](https://gitea.gklazycat.heiyu.space/emacs-taf/etaf/src/branch/main/docs/manual.md#gui-verification-tools)。

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

Research Shelf 场景还会关闭预览，再用同一个 SQLite 文件挂载新 Runtime。
重新选择已编辑记录并刷新列表后，已保存进度和 256 条记录总数必须保持不变。

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

## 性能

`benchmarks/performance-scenarios.el` 把 Research Shelf 的交互注册到工作区性能工具。
每个场景针对新建的 SQLite fixture mount 示例，重复一个公开事件：选行、切换主题、
筛选、翻页和缩放。批处理使用固定的 1413×62 viewport，GUI 模式跟随显示窗口。

```sh
make perf-list
make perf-check PERF_ARGS='--samples 30 --sets 3 --output-dir /tmp/shelf-perf'
```

选行、主题和缩放必须在一帧 16 ms 内完成；筛选和翻页会替换整页键控行，预算为
33 ms。这两个目标调用工作区的 `scripts/performance.py`，GUI 模式、基线和诊断
pass 见其手册。

仓库中的 Research Shelf 只是上述通用工作区的一个 consumer。它默认安装确定性的
256 条 SQLite fixture，每页显示 12 条；测试或压测时可以绑定
`etaf-research-shelf-fixture-size` 和 `etaf-research-shelf-page-size` 调整规模，
界面中激活 `Rows N` 可以输入 1–100。

## 开发

克隆后运行 `make setup-hooks`。提交变更前运行 `make check`；`make structure-check` 用于快速检查目录、命名和引用。

`make check` 运行规范检查、编译及 [tests/acceptance.json](tests/acceptance.json) 中的公共验收场景。`make test` 运行同一套公共 API 测试。清单涵盖全部维护的 Lisp 测试。GUI 与性能验收使用独立入口。
