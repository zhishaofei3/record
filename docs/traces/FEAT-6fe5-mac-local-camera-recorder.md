# FEAT-6fe5: Mac 本地摄像头录制软件

> mode: dev

## 当前产品状态（Before）
> 来源：`docs/product/modules/local-recorder/RecordingWorkspace.md`
> 组件模板级别：完整

当前产品地图已经定义了 `local-recorder` 模块和 `RecordingWorkspace` 组件骨架：应用围绕一个录制工作台组织摄像头预览、录制控制、虚拟背景和导出流程，但仓库仍处于 greenfield 状态，尚无实现代码。
现有规约层文档已经约束了几个关键行为：录制开始后设备必须锁定、虚拟背景的预览与导出效果必须一致、导出前必须确认保存路径。
本次需求将在这些设计期骨架之上，补充完整的本地摄像头录制交付规格。

## 场景
小明是一名需要录制个人讲解视频的 Mac 用户。他打开 Record，希望直接使用本机摄像头和麦克风录制一段可交付的视频。
在开始录制前，他需要确认当前使用哪一个摄像头、哪一个麦克风，并选择合适的输出分辨率，比如 1080p 或 4K。为了让画面更统一，他打开虚拟背景，希望系统把人物保留下来，并将背景替换为纯白色。

变更后：小明打开应用后，可以看到实时预览，选择摄像头、麦克风、分辨率，并决定是否开启白底虚拟背景。点击开始录制后，系统持续显示当前摄像头画面预览；点击停止录制后，用户可在导出前选择保存路径，系统输出 mp4 文件，并自动打开导出目录。如果录制前开启了虚拟背景，导出的 mp4 中必须保留该白底抠像效果。

## 关键规则
- 本次仅支持 macOS 原生本地应用，不依赖云端处理完成录制主流程。
- 本次仅支持摄像头录制模式，不包含屏幕录制功能实现，但架构需为后续录屏扩展预留空间。
- 录制前必须允许用户选择摄像头与麦克风输入设备。
- 录制开始后，摄像头和麦克风选择项锁定，录制过程中禁止切换输入设备。
- 录制进行中必须持续提供当前摄像头画面的实时预览。
- 用户可通过停止按钮主动结束录制。
- 分辨率预设至少包含 `720p`、`1080p`、`4K`。
- `4K` 允许因硬件能力限制不可用或自动降级，但需要给用户明确反馈。
- 虚拟背景本次仅交付“白色背景 + 人像抠图替换”。
- 若录制开始前开启虚拟背景，则导出的 mp4 必须保留虚拟背景效果，而不是只在预览中生效。
- 虚拟背景能力的内部设计需预留后续扩展到“自定义图片背景”与“背景模糊”。
- 录制结束后，导出前必须允许用户选择保存路径。
- 导出完成后，应用自动打开导出目录。
- UI 不要求显示录制时长或音量电平。

## 不变式影响（完整级组件必填）
- `RecordingWorkspace` 现有不变式“任意时刻只能存在一个活跃录制会话”必须保持不变。
- `RecordingWorkspace` 现有不变式“录制开始后设备必须锁定”必须保持不变，并在实现中落实到设备控件禁用态。
- `RecordingWorkspace` 与 `BackgroundProcessor` 现有不变式“虚拟背景的预览与导出效果必须一致”必须保持不变。
- `ExportPipeline` 现有不变式“导出前必须确认保存路径”必须保持不变。
- 新增实现不得破坏后续录屏扩展的接口边界，摄像头录制模式仍需保持单一稳定状态机。

## 验收标准
- [ ] 用户启动应用后可以看到本机摄像头实时预览。
- [ ] 用户可以在录制开始前选择可用摄像头设备。
- [ ] 用户可以在录制开始前选择可用麦克风设备。
- [ ] 用户可以在录制开始前选择 `720p`、`1080p`、`4K` 中的任一可用分辨率。
- [ ] 当设备不支持 `4K` 时，应用明确提示该分辨率不可用或已降级处理。
- [ ] 用户可以在录制开始前开启或关闭白底虚拟背景。
- [ ] 点击开始录制后，系统开始采集摄像头画面与麦克风声音。
- [ ] 录制进行中，界面持续展示当前摄像头画面预览。
- [ ] 录制进行中，设备选择控件处于禁用状态，用户无法切换摄像头或麦克风。
- [ ] 录制进行中，用户可以点击停止按钮结束录制。
- [ ] 停止录制后，系统在导出前提示用户选择保存路径。
- [ ] 点击确认导出后，系统生成可播放的 mp4 文件。
- [ ] 当录制前未开启虚拟背景时，导出 mp4 保留原始摄像头背景。
- [ ] 当录制前开启虚拟背景时，导出 mp4 保留白色背景抠像效果。
- [ ] 当虚拟背景处理失败时，系统向用户给出明确提示。
- [ ] 导出 mp4 的分辨率与用户录制前选择的分辨率一致；若因硬件能力触发降级，文件结果与降级后的实际录制配置一致。
- [ ] 导出完成后，应用自动打开导出目录。
- [ ] 主界面不显示录制时长或音量电平。
- [ ] 后续新增录屏模式时，无需推翻本次录制会话与导出链路的核心状态模型。

## Non-Goals（刻意不做）
- 本次不实现屏幕录制功能。
- 本次不实现摄像头与屏幕的混合录制。
- 本次不实现录制中的设备热切换。
- 本次不实现多种虚拟背景类型的正式交付，包含自定义图片背景与背景模糊。
- 本次不实现在线视频上传、云端转码、云端存储或分享链路。
- 本次不实现复杂剪辑、字幕、贴纸、美颜或后期编辑功能。
- 本次不在 UI 中显示录制时长、音量电平或复杂监控面板。
- 本次不覆盖 Windows 或 Linux 平台。

## 受影响的组件
- `docs/product/modules/local-recorder/RecordingWorkspace.md`（完整）：
  - 交互表 / 状态机：补全“预览中 / 已配置 / 录制中 / 停止中 / 待选择导出路径 / 导出中 / 导出完成 / 导出失败”等核心状态与转移
  - 状态：补充设备选择、分辨率选择、虚拟背景开关、录制控制、实时预览、导出路径选择、导出结果状态
  - 边界情况：补充无摄像头、无麦克风、权限未授权、设备被占用、录制中预览异常、停止后未选择路径、导出失败
  - 故障旅程：补充权限拒绝、设备初始化失败、录制中断、编码失败、导出文件失败的恢复策略
- `docs/product/modules/local-recorder/DeviceSelector.md`（标准）：
  - 交互表：补强摄像头/麦克风枚举、选择、录制中禁用态
  - 状态：明确空设备、单设备、多设备、禁用态
  - 边界情况：细化设备断开、默认设备变化
- `docs/product/modules/local-recorder/ResolutionProfile.md`（标准）：
  - 交互表：补强 `720p`、`1080p`、`4K` 预设展示与可用性判断
  - 状态：明确可用、不可用、降级提示
  - 边界情况：细化硬件能力不足与不同摄像头能力差异
- `docs/product/modules/local-recorder/BackgroundProcessor.md`（完整）：
  - 交互表 / 状态机：补强虚拟背景开关、分割成功、分割退化、输出合成、失败提示
  - 状态：明确关闭、开启处理中、开启成功、处理失败
  - 边界情况：细化人像识别不稳定、低性能设备帧率下降、处理链路不可用
  - 故障旅程：补充虚拟背景不可用时的提示与回退策略
- `docs/product/modules/local-recorder/ExportPipeline.md`（完整）：
  - 交互表 / 状态机：补强录制封装、停止收尾、导出路径确认、编码、mp4 写入完成/失败
  - 状态：明确待录制、录制中、待路径确认、导出中、导出成功、导出失败
  - 边界情况：细化磁盘空间不足、写文件失败、编码异常、中断退出、用户取消保存
  - 故障旅程：补充导出失败恢复、路径取消与自动打开目录行为说明

## 模式
frontend

## API 交互（如有）
- 无外部 API 依赖；本次为本地 macOS 原生能力实现。
- 设备采集、虚拟背景处理、编码导出均在本地完成。

## 产品地图更新要求
开发完成后，`/update-map` 须：
- [ ] 更新 `docs/product/PRODUCT-MAP.md`
- [ ] 更新 `docs/product/modules/local-recorder/index.md`
- [ ] 更新 `docs/product/modules/local-recorder/RecordingWorkspace.md`（级别：完整）
- [ ] 更新 `docs/product/modules/local-recorder/DeviceSelector.md`（级别：标准）
- [ ] 更新 `docs/product/modules/local-recorder/ResolutionProfile.md`（级别：标准）
- [ ] 更新 `docs/product/modules/local-recorder/BackgroundProcessor.md`（级别：完整）
- [ ] 更新 `docs/product/modules/local-recorder/ExportPipeline.md`（级别：完整）
- [ ] 在上述组件中补齐交互表、状态机、边界情况、不变式与故障旅程

## 治理合规（case-specific，非 PATCH 必填）
### PD 边界定义
- 安全护栏：仅处理本地摄像头与麦克风录制，不涉及云端上传或外发
- 度量目标：成功导出包含摄像头画面、麦克风声音且符合用户预设分辨率的 mp4 文件；若开启虚拟背景，导出文件必须保留白底抠像效果
- 性能约束：常用分辨率 `720p`、`1080p`、`4K` 可选；`4K` 可因硬件能力限制降级，但必须明确反馈；开启虚拟背景时导出结果必须保留效果
- A11y 要求：需保证基础键盘可操作性和权限提示可读性
### 研发补充（基于代码上下文）
- 已有约束：产品文档骨架已经定义了设备锁定、预览与导出一致性、路径确认后再落盘等关键不变式
- 风险点：`4K + 虚拟背景` 对本地算力和编码链路压力较大，可能影响预览流畅度、录制稳定性或导出速度
- 风险点：macOS 摄像头/麦克风权限未授权会阻断主流程，需在首次进入时提供明确授权引导
- 风险点：虚拟背景若仅作用于预览层而未接入导出链路，会造成预览与文件不一致
- 风险点：导出前路径选择若与停止录制收尾耦合不清，可能造成文件未正确落盘或用户误以为已保存
- 建议补充：定义最低支持的 macOS 版本以及虚拟背景在低性能设备上的降级策略
- 建议补充：定义导出文件默认命名规则，以及用户取消保存时的行为

## Open Issues（待决问题）
- 导出文件的默认命名规则当前尚未确定
- 虚拟背景处理失败时，是否允许用户继续录制原始背景视频，当前尚未确定
- 录制进行中是否需要显示“正在录制”的状态标识，当前尚未确定

## Baseline
> 以下文件的内容哈希记录了起草本需求时的产品状态。

| 文件 | SHA256 前 8 位 |
|------|---------------|
| docs/product/PRODUCT-MAP.md | 15d69bc3 |
| docs/product/modules/local-recorder/index.md | 98291aec |
| docs/product/modules/local-recorder/RecordingWorkspace.md | a000eeff |

## 实现追溯

### 代码变更
- `Package.swift` — 新增 macOS Swift Package，拆分 `RecordCore` 与 `RecordApp`
- `Sources/RecordCore/Domain/RecorderContracts.swift` — 定义录制、分辨率、设备与导出合约
- `Sources/RecordCore/Domain/RecorderStateMachine.swift` — 定义录制状态机与非法转换保护
- `Sources/RecordCore/Processing/PersonSegmentationProcessor.swift` — 新增 Vision 白底人像分割处理
- `Sources/RecordCore/Capture/RecorderEngine.swift` — 实现 AVFoundation 采集、实时预览、mp4 临时录制与导出提交
- `Sources/RecordApp/RecordApp.swift` — 新增 SwiftUI 原生桌面应用入口
- `Sources/RecordApp/RecorderViewModel.swift` — 实现录制工作台状态、保存面板与导出目录打开流程
- `Sources/RecordApp/ContentView.swift` — 实现摄像头预览、设备选择、分辨率选择、虚拟背景和录制控制界面
- `Tests/RecordCoreTests/RecorderDomainTests.swift` — 新增分辨率降级和录制状态机测试
- `Record.xcodeproj/project.pbxproj` — 新增可提交的 Xcode 工程，包含 `RecordCore`、`Record`、`RecordCoreTests` 目标和共享 scheme
- `scripts/generate_xcodeproj.rb` — 新增工程生成脚本，确保 `.xcodeproj` 可再生
- `README.md` / `LICENSE` / `.gitignore` — 补齐开源仓库基础元信息

### 架构决策记录（ADR）
**决策**：录制阶段先写入临时 mp4，再在停止录制后由用户选择最终保存路径并移动文件。
**考虑过的替代方案**：开始录制前先要求用户选择保存路径；录制结束后再做完整离线转码导出。
**理由**：`AVAssetWriter` 需要在录制开始时持有输出 URL，而需求要求在导出前选择路径。临时文件方案能同时满足两边约束。
**权衡**：获得了录制中无阻塞的写入链路与停止后再选路径的交互；代价是需要管理临时文件和取消保存时的清理策略。

**决策**：虚拟背景处理失败时采用 fail-open 策略，提示用户并继续输出原始摄像头画面。
**考虑过的替代方案**：处理失败即中断录制；处理失败后强制关闭增强并阻止继续。
**理由**：录制主流程的可用性优先于特效完整性，尤其在本地硬件能力差异较大的场景下。
**权衡**：获得了更稳定的录制连续性；代价是个别失败场景下导出结果可能退回原始背景。

**决策**：为原生工程同时保留 Swift Package 和可再生 Xcode Project 两条入口。
**考虑过的替代方案**：只保留 Swift Package；直接手维护 `.pbxproj`。
**理由**：Swift Package 适合代码组织和命令行构建，Xcode Project 适合签名、本地运行和后续分发；生成脚本能避免手工维护项目文件。
**权衡**：获得了更稳定的 Xcode 运行链路；代价是仓库里多了一份生成脚本和项目文件。

### 本机验证
- `swift test` 通过，7 个测试成功。
- `xcodebuild -project Record.xcodeproj -scheme Record -configuration Debug -destination 'platform=macOS' build` 通过。
- `xcodebuild -project Record.xcodeproj -scheme RecordCoreTests -configuration Debug -destination 'platform=macOS' test` 通过。
- 当前机器可枚举到 `MacBook Pro Camera`、`Airtime Virtual Camera`、`MacBook Pro Microphone` 等设备。
- 调试版 `Record.app` 已可直接拉起并常驻进程。
- 录制、导出、虚拟背景的完整 GUI 交互链路未在本轮自动化验证，因为当前环境无法安全自动点击原生 macOS 窗口与 TCC 权限弹窗。

### 迭代统计
- Coder 迭代次数：2
- 审计得分：88/100
- 新增技术债：1 项
