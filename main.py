#!/usr/bin/env python3
"""
YouSpeak - 语音输入工具
按住 右Option键 说话，松开后文字自动打到光标位置
"""

import threading
import time
import sys
import numpy as np
import sounddevice as sd
from dashscope.audio.asr import Recognition, RecognitionCallback, RecognitionResult
from pynput import keyboard
import Quartz

# ============ 配置 ============
API_KEY = "sk-047a70e7b12a4eb6bc49bc7145939a5d"
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

        time.sleep(0.004)   # 避免输入太快被部分 app 丢字


class ASRCallback(RecognitionCallback):
    """DashScope 实时 ASR 回调"""

    def on_open(self):
        print("[ASR] 连接成功")

    def on_complete(self):
        print("[ASR] 识别结束")

    def on_error(self, result):
        print(f"[ASR 错误] {result}")

    def on_event(self, result: RecognitionResult):
        if result.status_code != 200:
            return
        sentence = result.get_sentence()
        if not sentence or "text" not in sentence:
            return
        text = sentence["text"]
        if RecognitionResult.is_sentence_end(sentence):
            # 句子结束，实际输入文字
            print(f"\n[输入] {text}")
            threading.Thread(target=type_text, args=(text,), daemon=True).start()
        else:
            # 中间结果，仅打印预览
            print(f"[识别中] {text}   ", end="\r", flush=True)


class SpeechApp:
    def __init__(self):
        self.is_recording = False
        self.recognition: Recognition | None = None
        self.audio_stream: sd.InputStream | None = None
        self._lock = threading.Lock()

    # -------- 音频回调 --------

    def _audio_callback(self, indata, frames, time_info, status):
        if not self.is_recording or self.recognition is None:
            return
        pcm = (indata[:, 0] * 32767).astype(np.int16).tobytes()
        self.recognition.send_audio_frame(pcm)

    # -------- 录音控制 --------

    def start_recording(self):
        with self._lock:
            if self.is_recording:
                return
            print("\n🎤 录音中…（松开 右Option 停止）")
            self.recognition = Recognition(
                model="paraformer-realtime-v2",
                format="pcm",
                sample_rate=SAMPLE_RATE,
                api_key=API_KEY,
                callback=ASRCallback(),
            )
            self.recognition.start()
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
            print("\n⏹ 处理中…")
            self.is_recording = False
            if self.audio_stream:
                self.audio_stream.stop()
                self.audio_stream.close()
                self.audio_stream = None
            if self.recognition:
                self.recognition.stop()
                self.recognition = None

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
