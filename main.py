#!/usr/bin/env python3
"""
YouSpeak - 语音输入工具
按住 右Option键 说话，松开后文字自动打到光标位置
"""

import threading
import time
import sys
import os
import numpy as np
from dotenv import load_dotenv

load_dotenv()
import sounddevice as sd
from dashscope.audio.asr import Recognition, RecognitionCallback, RecognitionResult
from pynput import keyboard
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


class SpeechApp:
    def __init__(self):
        self.is_recording = False
        self.audio_buffer: list[bytes] = []
        self.audio_stream: sd.InputStream | None = None
        self._lock = threading.Lock()

    # -------- 音频回调：录到 buffer --------

    def _audio_callback(self, indata, frames, time_info, status):
        if not self.is_recording:
            return
        pcm = (indata[:, 0] * 32767).astype(np.int16).tobytes()
        self.audio_buffer.append(pcm)

    # -------- 录音完成后发给 ASR --------

    def _transcribe(self, audio_buffer: list[bytes]):
        if not audio_buffer:
            return

        print("⏳ 识别中…")
        result_text: list[str] = []
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
                    result_text.append(s["text"])

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
        try:
            rec.stop()
        except Exception:
            pass
        done.wait(timeout=15)

        audio_buffer.clear()

        text = "".join(result_text)
        if text:
            print(f"[输入] {text}")
            type_text(text)
        else:
            print("（未识别到内容）")

    # -------- 录音控制 --------

    def start_recording(self):
        with self._lock:
            if self.is_recording:
                return
            print("\n🎤 录音中…（松开 右⌥ 停止）")
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

    def stop_recording(self):
        with self._lock:
            if not self.is_recording:
                return
            self.is_recording = False
            if self.audio_stream:
                self.audio_stream.stop()
                self.audio_stream.close()
                self.audio_stream = None
            # 把 buffer 快照传给识别线程，主线程继续响应热键
            buf = self.audio_buffer
            self.audio_buffer = []
        threading.Thread(target=self._transcribe, args=(buf,), daemon=True).start()

    # -------- 键盘监听 --------

    def _on_press(self, key):
        if key == HOTKEY:
            threading.Thread(target=self.start_recording, daemon=True).start()

    def _on_release(self, key):
        if key == HOTKEY:
            threading.Thread(target=self.stop_recording, daemon=True).start()

    # -------- 入口 --------

    def run(self):
        print("=" * 42)
        print("  YouSpeak 语音输入  (按住 右⌥ 说话)")
        print("  Ctrl+C 退出")
        print("=" * 42)
        with keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        ) as listener:
            try:
                listener.join()
            except KeyboardInterrupt:
                self.stop_recording()
                print("\n再见！")


if __name__ == "__main__":
    SpeechApp().run()
