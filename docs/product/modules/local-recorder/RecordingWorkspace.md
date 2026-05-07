# RecordingWorkspace — 录制工作台

> **模块**：[Local Recorder](index.md) | **级别**：完整 | **最后更新**：2026-05-07

## 关系

| 方向 | 类型 | 目标 | 说明 |
|------|------|------|------|
| → | 依赖 | [DeviceSelector](DeviceSelector.md) | 录制开始前需要确定摄像头与麦克风输入 |
| → | 依赖 | [ResolutionProfile](ResolutionProfile.md) | 录制开始前需要确定输出分辨率 |
| → | 依赖 | [BackgroundProcessor](BackgroundProcessor.md) | 需要统一管理虚拟背景的预览和导出效果 |
| → | 依赖 | [ExportPipeline](ExportPipeline.md) | 停止录制后通过导出管线完成 mp4 写入 |
| ← | 被依赖 | [DeviceSelector](DeviceSelector.md) | 设备选择结果回流到工作台状态 |
| ← | 被依赖 | [ResolutionProfile](ResolutionProfile.md) | 分辨率能力判断回流到工作台状态 |
| ← | 被依赖 | [BackgroundProcessor](BackgroundProcessor.md) | 背景处理状态回流到工作台提示和最终输出 |
| ← | 被依赖 | [ExportPipeline](ExportPipeline.md) | 导出成功或失败状态回流到工作台 |

## 功能

统一承载摄像头预览、录制控制、配置锁定、错误提示和导出完成反馈。

## 界面结构

```text
+--------------------------------------------------------------+
| Preview Canvas                                               |
| [ live camera / white background preview ]                   |
+--------------------------------------------------------------+
| Camera | Mic | Resolution | Virtual Background | Record Btn  |
+--------------------------------------------------------------+
| Status / Error / Export Result                               |
+--------------------------------------------------------------+
```

## 不变式（必须永远成立的规则）

- 任意时刻只能存在一个活跃录制会话。
- 录制开始后，摄像头和麦克风选择必须锁定，直到会话结束。
- 当虚拟背景开启时，预览与导出必须保持同一效果语义。
- 导出前必须确认保存路径，不能自动写入未确认位置。

## 状态机

| 当前状态 | 触发事件 | 动作 | 下一状态 |
|---------|---------|------|---------|
| `booting` | 初始化成功 | 建立预览流并加载默认配置 | `preview-ready` |
| `booting` | 设备或权限失败 | 显示设备或权限错误 | **`setup-error`** |
| `preview-ready` | 修改录制前配置 | 更新工作台配置 | `preview-ready` |
| `preview-ready` | 点击开始录制 | 锁定配置并启动采集 | `recording` |
| `recording` | 点击停止录制 | 停止采集并准备导出 | `awaiting-export-path` |
| `recording` | 录制中断 | 显示中断错误 | **`recording-error`** |
| `awaiting-export-path` | 用户确认路径 | 调用导出管线 | `exporting` |
| `awaiting-export-path` | 用户取消路径选择 | 保持待确认状态或结束会话 | `awaiting-export-path` |
| `exporting` | 导出成功 | 展示成功并打开导出目录 | `export-done` |
| `exporting` | 导出失败 | 展示错误并允许重试 | **`export-error`** |
| **`setup-error`** | 用户修复权限或设备问题 | 重新初始化预览 | `booting` |
| **`recording-error`** | 用户确认恢复 | 清理会话并回到预览 | `preview-ready` |
| **`export-error`** | 用户重试导出 | 重新确认路径或继续导出 | `awaiting-export-path` |

## 故障旅程

| 故障场景 | 检测方式 | 降级策略 | 恢复路径 |
|---------|---------|---------|---------|
| 摄像头或麦克风权限被拒绝 | 初始化采集失败 | 显示权限提示并阻止开始录制 | 用户授权后重新初始化 |
| 设备不存在或被占用 | 枚举或打开设备失败 | 显示设备错误并禁用录制按钮 | 用户更换设备后重试 |
| 录制过程中采集流中断 | 采集会话抛出错误 | 停止当前会话并保留错误信息 | 用户确认后返回预览态 |
| 导出路径未确认 | 保存对话框取消 | 不写入文件并保留待确认态 | 用户重新选择路径 |
| 导出写入失败 | 编码或写文件失败 | 展示导出错误并允许重试 | 用户重试导出 |

## 数据契约引用

| 合约 | 路径 | 说明 |
|------|------|------|
| STUB | docs/specs/STUB | 实现后补充录制会话和导出契约 |

## 性能约束

- 预览连续性：录制进行中必须持续显示当前摄像头画面。
- 状态切换：开始录制、停止录制和进入导出态应有明确即时反馈。

## Non-Goals（刻意不做）

- 不负责屏幕录制。
- 不负责复杂后期编辑。

## Open Issues（待决设计问题）

- 录制中是否需要独立的计时器或录制时长展示仍待后续版本确认。

## 技术摘要

- 以录制会话状态机为中枢，协调输入配置、视频处理和导出收尾。

## 已知限制

- 当前界面仅通过状态徽标提示录制状态，不显示录制时长。
- 尚无 `4K + 虚拟背景` 在低性能设备上的真实性能基线。
