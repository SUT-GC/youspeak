#!/usr/bin/env python3
"""
YouSpeak - 语音输入工具
按住 右Option键 说话，松开后文字自动打到光标位置
"""

import threading
import time
import signal
import sys
import os
import numpy as np
from dotenv import load_dotenv

load_dotenv()

import sounddevice as sd
from dashscope.audio.asr import Recognition, RecognitionCallback, RecognitionResult
from pynput import keyboard
import objc
import AppKit
import Foundation
import Quartz

# ============ 配置 ============
API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
if not API_KEY:
    print("❌ 请在项目目录创建 .env 文件，填入：")
    print("   DASHSCOPE_API_KEY=sk-xxxxxxxx")
    sys.exit(1)
HOTKEY = keyboard.Key.alt_r   # 右 Option 键，可改成其他键
SAMPLE_RATE = 16000
CHUNK_FRAMES = 3200            # 200ms per chunk @ 16kHz
# ==============================


def type_text(text: str):
    """通过 CGEvent 把文字直接打到当前光标位置，不走剪贴板"""
    src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    for char in text:
        ev_down = Quartz.CGEventCreateKeyboardEvent(src, 0, True)
        Quartz.CGEventKeyboardSetUnicodeString(ev_down, len(char), char)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev_down)
        ev_up = Quartz.CGEventCreateKeyboardEvent(src, 0, False)
        Quartz.CGEventKeyboardSetUnicodeString(ev_up, len(char), char)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev_up)
        time.sleep(0.004)


# -------- 浮窗（可覆盖全屏 App）--------

class OverlayController(AppKit.NSObject):
    """
    系统 HUD 风格浮窗，悬浮于所有窗口之上（包括全屏 App）。
    UI 操作全部通过 performSelectorOnMainThread 派发到主线程。
    """

    W = 180
    H = 46

    def init(self):
        self = objc.super(OverlayController, self).init()
        self._window = None
        self._label = None
        return self

    def setup(self):
        """在主线程调用一次"""
        W, H = self.W, self.H
        panel = AppKit.NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            Foundation.NSMakeRect(0, 0, W, H),
            AppKit.NSWindowStyleMaskBorderless,
            AppKit.NSBackingStoreBuffered,
            False,
        )
        # 浮在全屏 App 之上
        panel.setLevel_(AppKit.NSStatusWindowLevel + 1)
        panel.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorStationary
        )
        panel.setOpaque_(False)
        panel.setAlphaValue_(0.95)
        panel.setHasShadow_(True)

        # 系统 HUD 磨砂玻璃背景
        effect = AppKit.NSVisualEffectView.alloc().initWithFrame_(
            Foundation.NSMakeRect(0, 0, W, H)
        )
        effect.setMaterial_(AppKit.NSVisualEffectMaterialHUDWindow)
        effect.setBlendingMode_(AppKit.NSVisualEffectBlendingModeBehindWindow)
        effect.setState_(AppKit.NSVisualEffectStateActive)
        effect.setWantsLayer_(True)
        effect.layer().setCornerRadius_(12.0)
        effect.layer().setMasksToBounds_(True)
        panel.setContentView_(effect)

        # 文字标签
        label = AppKit.NSTextField.alloc().initWithFrame_(
            Foundation.NSMakeRect(0, 11, W, 24)
        )
        label.setStringValue_("🎤  录音中…")
        label.setAlignment_(AppKit.NSTextAlignmentCenter)
        label.setBordered_(False)
        label.setEditable_(False)
        label.setSelectable_(False)
        label.setDrawsBackground_(False)
        label.setTextColor_(AppKit.NSColor.whiteColor())
        label.setFont_(AppKit.NSFont.systemFontOfSize_(14))
        effect.addSubview_(label)

        # 屏幕居中偏下
        screen_w = AppKit.NSScreen.mainScreen().frame().size.width
        panel.setFrameOrigin_(Foundation.NSMakePoint((screen_w - W) / 2, 100))

        self._window = panel
        self._label = label

    # --- 主线程 selector（方法名末尾 _ 对应 ObjC selector 的 :）---

    def doShow_(self, _):
        self._label.setStringValue_("🎤  录音中…")
        self._window.orderFront_(None)

    def doShowProcessing_(self, _):
        self._label.setStringValue_("⏳  识别中…")

    def doHide_(self, _):
        self._window.orderOut_(None)

    # --- 后台线程调用入口 ---

    def show(self):
        self.performSelectorOnMainThread_withObject_waitUntilDone_(
            b"doShow:", None, False
        )

    def show_processing(self):
        self.performSelectorOnMainThread_withObject_waitUntilDone_(
            b"doShowProcessing:", None, False
        )

    def hide(self):
        self.performSelectorOnMainThread_withObject_waitUntilDone_(
            b"doHide:", None, False
        )


# -------- 主逻辑 --------

class SpeechApp:
    def __init__(self, overlay: OverlayController):
        self.overlay = overlay
        self.is_recording = False
        self.audio_buffer: list[bytes] = []
        self.audio_stream: sd.InputStream | None = None
        self._lock = threading.Lock()

    def _audio_callback(self, indata, frames, time_info, status):
        if not self.is_recording:
            return
        pcm = (indata[:, 0] * 32767).astype(np.int16).tobytes()
        self.audio_buffer.append(pcm)

    def _transcribe(self, audio_buffer: list[bytes]):
        if not audio_buffer:
            self.overlay.hide()
            return

        # 用 dict 按 sentence_id 去重：同一句话可能触发多次 sentence_end，只保留最新的
        result_sentences: dict[int, str] = {}
        done = threading.Event()

        class CB(RecognitionCallback):
            def on_open(self): pass
            def on_complete(self): done.set()
            def on_error(self, r):
                print(f"[ASR 错误] {r}")
                done.set()
            def on_event(self, r: RecognitionResult):
                if r.status_code != 200:
                    return
                s = r.get_sentence()
                if s and "text" in s and RecognitionResult.is_sentence_end(s):
                    sid = s.get("sentence_id", len(result_sentences))
                    result_sentences[sid] = s["text"]

        rec = Recognition(
            model="paraformer-realtime-v2",
            format="pcm",
            sample_rate=SAMPLE_RATE,
            api_key=API_KEY,
            callback=CB(),
        )
        rec.start()
        for chunk in audio_buffer:
            try:
                rec.send_audio_frame(chunk)
            except Exception:
                break
        audio_buffer.clear()
        try:
            rec.stop()
        except Exception:
            pass
        done.wait(timeout=15)

        self.overlay.hide()

        text = "".join(result_sentences[k] for k in sorted(result_sentences))
        if text:
            print(f"[输入] {text}")
            type_text(text)
        else:
            print("（未识别到内容）")

    def start_recording(self):
        with self._lock:
            if self.is_recording:
                return
            self.audio_buffer = []
            self.audio_stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=1,
                dtype=np.float32,
                blocksize=CHUNK_FRAMES,
                callback=self._audio_callback,
            )
            self.audio_stream.start()
            self.is_recording = True
            self.overlay.show()

    def stop_recording(self):
        with self._lock:
            if not self.is_recording:
                return
            self.is_recording = False
            self.overlay.show_processing()
            if self.audio_stream:
                self.audio_stream.stop()
                self.audio_stream.close()
                self.audio_stream = None
            buf = self.audio_buffer
            self.audio_buffer = []
        threading.Thread(target=self._transcribe, args=(buf,), daemon=True).start()

    def _on_press(self, key):
        if key == HOTKEY:
            threading.Thread(target=self.start_recording, daemon=True).start()

    def _on_release(self, key):
        if key == HOTKEY:
            threading.Thread(target=self.stop_recording, daemon=True).start()


def main():
    # 不显示 Dock 图标
    ns_app = AppKit.NSApplication.sharedApplication()
    ns_app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    overlay = OverlayController.alloc().init()
    overlay.setup()

    speech_app = SpeechApp(overlay)

    # Ctrl+C 退出
    def handle_sigint(sig, frame):
        print("\n再见！")
        os._exit(0)
    signal.signal(signal.SIGINT, handle_sigint)

    # 键盘监听跑在子线程（NSApp 需要占用主线程）
    def run_keyboard():
        with keyboard.Listener(
            on_press=speech_app._on_press,
            on_release=speech_app._on_release,
        ) as listener:
            listener.join()

    threading.Thread(target=run_keyboard, daemon=True).start()

    print("=" * 42)
    print("  YouSpeak 语音输入  (按住 右⌥ 说话)")
    print("  Ctrl+C 退出")
    print("=" * 42)

    ns_app.run()


if __name__ == "__main__":
    main()
