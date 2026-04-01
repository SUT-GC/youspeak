# YouSpeak

macOS 语音输入工具，按住快捷键说话，文字实时打到光标位置。支持任意输入框，包括浏览器。

## 特性

- **按住说话，松开停止** - 右 Option 键触发，无需手动切换
- **实时流式识别** - 基于阿里云 DashScope Paraformer，边说边出字
- **直接输入，不走剪贴板** - 通过 macOS CGEvent 模拟键盘，不影响你的复制内容
- **全局生效** - 任意 App、浏览器输入框均可使用
- **本地 M 系列芯片优化** - 依赖轻量，无需 Xcode

## 环境要求

- macOS（Apple Silicon M 系列）
- Python 3.10+
- 阿里云 DashScope API Key（[申请地址](https://dashscope.aliyun.com)）

## 安装

```bash
git clone git@github.com:SUT-GC/youspeak.git
cd youspeak

python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## 配置

复制 `.env.example` 为 `.env`，填入你的 DashScope API Key：

```bash
cp .env.example .env
# 编辑 .env，填入真实 key
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxx
```

默认快捷键是右 Option 键，可修改 `HOTKEY` 变量：

```python
from pynput import keyboard
HOTKEY = keyboard.Key.alt_r   # 右 Option
# HOTKEY = keyboard.Key.f9    # 或改成 F9
```

## 运行

```bash
.venv/bin/python3 main.py
```

**首次运行** macOS 会弹出两个权限请求，需要全部允许：

- **麦克风** - 用于录音
- **辅助功能（Accessibility）** - 用于模拟键盘输入

> 系统设置 → 隐私与安全性 → 辅助功能，手动添加你的终端 App（Terminal / iTerm2）

## 使用

1. 运行程序，终端出现提示后进入任意输入框
2. **按住右 Option（⌥）键** 开始说话
3. **松开**，识别完成后文字自动打入光标位置

## 技术栈

| 功能 | 实现 |
|---|---|
| 语音识别 | DashScope `paraformer-realtime-v2` 实时流式 |
| 录音 | `sounddevice` |
| 全局热键 | `pynput` |
| 键盘模拟 | `pyobjc` Quartz CGEvent |
