# FEAT-6fe5 OpenSpec

> 来源：`docs/traces/FEAT-6fe5-mac-local-camera-recorder.md`
> 组件：`RecordingWorkspace`（完整），`DeviceSelector`（标准），`ResolutionProfile`（标准），`BackgroundProcessor`（完整），`ExportPipeline`（完整）

## 数据结构

| 结构 | 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `DeviceDescriptor` | `id` | `String` | 是 | 设备唯一标识 |
| `DeviceDescriptor` | `name` | `String` | 是 | 用户可见名称 |
| `ResolutionPreset` | `p720 \| p1080 \| p4K` | `Enum` | 是 | 录制分辨率预设 |
| `ResolutionDecision` | `requested` | `ResolutionPreset` | 是 | 用户请求的分辨率 |
| `ResolutionDecision` | `actual` | `ResolutionPreset` | 是 | 实际录制分辨率 |
| `ResolutionDecision` | `message` | `String?` | 否 | 降级或提示信息 |
| `RecorderBootstrap` | `videoDevices` | `[DeviceDescriptor]` | 是 | 当前可用摄像头 |
| `RecorderBootstrap` | `audioDevices` | `[DeviceDescriptor]` | 是 | 当前可用麦克风 |
| `RecorderBootstrap` | `selectedVideoDeviceID` | `String` | 是 | 当前选中摄像头 |
| `RecorderBootstrap` | `selectedAudioDeviceID` | `String` | 是 | 当前选中麦克风 |
| `RecorderBootstrap` | `resolutionSupport` | `ResolutionSupportMatrix` | 是 | 当前摄像头能力矩阵 |
| `RecorderBootstrap` | `resolutionDecision` | `ResolutionDecision` | 是 | 选定分辨率的实际决策 |
| `RecorderConfiguration` | `videoDeviceID` | `String` | 是 | 录制摄像头 |
| `RecorderConfiguration` | `audioDeviceID` | `String` | 是 | 录制麦克风 |
| `RecorderConfiguration` | `requestedResolution` | `ResolutionPreset` | 是 | 请求分辨率 |
| `RecorderConfiguration` | `actualResolution` | `ResolutionPreset` | 是 | 实际录制分辨率 |
| `RecorderConfiguration` | `virtualBackgroundEnabled` | `Bool` | 是 | 是否启用白底虚拟背景 |

## 状态枚举

| 枚举 | 成员 |
|------|------|
| `RecordingPhase` | `booting`, `previewReady`, `recording`, `awaitingExportPath`, `exporting`, `exportComplete(URL)`, `error(String)` |
| `ResolutionAvailability` | `available`, `unavailable` |
| `RecorderEvent` | `bootSucceeded`, `bootFailed(String)`, `startRecording`, `stopRecording`, `exportRequested`, `exportSucceeded(URL)`, `exportFailed(String)`, `recover` |

## 常量

| 常量 | 值 | 说明 |
|------|----|------|
| `previewFrameInterval` | `1 / 15s` | 预览节流，避免 UI 更新过密 |
| `videoPixelFormat` | `32BGRA` | 预览和处理统一像素格式 |
| `outputFileType` | `mp4` | 最终导出格式 |

## 状态转换

| 当前状态 | 触发 | 条件 | 下一状态 |
|---------|------|------|---------|
| `booting` | `bootSucceeded` | 权限和设备可用 | `previewReady` |
| `booting` | `bootFailed` | 权限/设备异常 | `error` |
| `previewReady` | `startRecording` | 配置有效 | `recording` |
| `recording` | `stopRecording` | 用户点击停止 | `awaitingExportPath` |
| `awaitingExportPath` | `exportRequested` | 用户确认保存路径 | `exporting` |
| `exporting` | `exportSucceeded` | 临时文件移动成功 | `exportComplete` |
| `exporting` | `exportFailed` | 写文件或移动失败 | `error` |
| `error` | `recover` | 用户重试 | `previewReady` |
| `exportComplete` | `startRecording` | 开启新会话 | `recording` |

## 边界情况

| 场景 | 处理策略 |
|------|---------|
| 摄像头不支持 `4K` | 自动回退到下一个可用预设并给出提示 |
| 用户取消保存对话框 | 保留待导出状态，允许再次选择保存路径 |
| 虚拟背景处理失败 | 提示用户，并回退到原始画面继续预览/录制 |
| 写文件失败 | 保留临时文件和错误提示，允许再次导出 |

## 不变式

- 任意时刻只能存在一个活跃录制会话。
- 录制开始后，摄像头和麦克风选择必须锁定。
- 若开启虚拟背景，预览和导出必须使用同一效果语义。
- 最终 mp4 文件必须晚于路径确认步骤落盘到用户选择的位置。
- 若分辨率被降级，UI 状态和实际写入分辨率必须一致。

## 故障旅程

| 故障场景 | 检测方式 | 降级策略 | 恢复路径 |
|---------|---------|---------|---------|
| 摄像头/麦克风权限被拒绝 | 权限请求失败 | 阻止进入可录制态并提示授权 | 用户授权后重新初始化 |
| 视频流中断 | 样本流停止或 writer 失败 | 结束会话并显示错误 | 用户恢复后重新开始 |
| 分割模型不可用 | Vision 请求抛错 | 提示失败并回退到原始背景 | 用户关闭或重试虚拟背景 |
| 目标路径写入失败 | 文件移动/编码失败 | 保留临时文件与错误消息 | 用户重新选择保存路径 |
