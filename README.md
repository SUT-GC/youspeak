# YouSpeak

macOS 语音输入工具，按住快捷键说话，文字实时打到光标位置。支持任意输入框，包括浏览器。

**[下载 DMG](https://github.com/SUT-GC/youspeak/releases/tag/1.0/YouSpeak.zip)** · [主页](https://sut-gc.github.io/youspeak/)

## 特性

- **按住说话，松开停止** — 默认右 Option 键，可在设置中自定义
- **实时流式识别** — 基于阿里云 DashScope Paraformer，边说边出字
- **AI 润色** — 可选接入 Qwen / 豆包，自动修正错字、优化表达
- **不走剪贴板** — 通过 CGEvent 模拟键盘，不影响复制内容
- **全局生效** — 任意 App、浏览器输入框均可使用

## 系统要求

- macOS 13 Ventura 及以上
- Apple Silicon 或 Intel
- 阿里云 DashScope API Key（[申请](https://dashscope.aliyun.com)，有免费额度）

## 安装

1. 下载 [YouSpeak.zip](https://github.com/SUT-GC/youspeak/releases/tag/1.0/YouSpeak.zip)
2. 打开 DMG，将 YouSpeak.app 拖入 Applications
3. 首次启动按提示授权**麦克风**和**辅助功能**权限

## 配置

打开 YouSpeak → 点击菜单栏图标 → **设置**：

| 项目 | 说明 |
| ---- | ---- |
| ASR API Key | DashScope API Key（必填） |
| 快捷键 | 默认右 Option，可自定义 |
| AI 润色 | 开启后接入 Qwen 或豆包润色文字 |
| LLM API Key | 润色功能所需的 API Key |

## 使用

1. 启动 YouSpeak，菜单栏出现图标
2. 点击任意输入框，定位光标
3. **按住右 Option（⌥）**，开口说话
4. **松开**，识别结果自动打入

## 从源码构建

需要 Xcode 15+。

```bash
git clone https://github.com/SUT-GC/youspeak.git
cd youspeak/swift
xcodebuild -project YouSpeak.xcodeproj -scheme YouSpeak -configuration Debug build
```

发布 DMG：

```bash
cd swift && ./release.sh
```

## 技术栈

| 功能 | 实现 |
| ---- | ---- |
| 语音识别 | DashScope Paraformer-realtime-v2 WebSocket 流式 |
| 录音 | AVAudioEngine，16 kHz PCM mono |
| 全局热键 | CGEvent tap |
| 键盘模拟 | CGEvent，字符逐个投递 |
| UI | SwiftUI + AppKit menubar |
