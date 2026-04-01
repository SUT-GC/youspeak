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
from dashscope import Generation
from pynput import keyboard
import Foundation
import AppKit
import Quartz

# ============ 配置 ============
API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
if not API_KEY:
    print("❌ 请在项目目录创建 .env 文件，填入：")
    print("   DASHSCOPE_API_KEY=sk-xxxxxxxx")
    sys.exit(1)
HOTKEY = keyboard.Key.alt_r   # 右 Option 键
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


def polish_text(raw: str) -> str:
    """用 Qwen 润色 ASR 原始文本：修错别字、去重复、整理语义"""
    try:
        resp = Generation.call(
            model="qwen-turbo",
            api_key=API_KEY,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "你是语音识别文本的后处理助手。"
                        "用户给你一段 ASR 原始输出，可能有错别字、重复词语或语义不通顺。"
                        "请直接输出修正后的文本，不要解释，不要加任何前缀或后缀，保持原意，尽量少改动。"
                    ),
                },
                {"role": "user", "content": raw},
            ],
        )
        if resp.status_code == 200:
            return resp.output.text.strip()
    except Exception as e:
        print(f"[润色失败] {e}")
    return raw


class SpeechApp:
    def __init__(self):
        self.is_recording = False
        self.audio_buffer: list[bytes] = []
        self.audio_stream: sd.InputStream | None = None
        self._record_lock = threading.Lock()
        # 保证同一时间只有一个转录+输出在运行，防止快速按键导致文字交叉
        self._transcribe_lock = threading.Lock()

    def _audio_callback(self, indata, frames, time_info, status):
        if not self.is_recording:
            return
        pcm = (indata[:, 0] * 32767).astype(np.int16).tobytes()
        self.audio_buffer.append(pcm)

    def _transcribe(self, audio_buffer: list[bytes]):
        with self._transcribe_lock:
            if not audio_buffer:
                return

            result_sentences: dict[int, str] = {}
            all_sent = threading.Event()
            done = threading.Event()

            class CB(RecognitionCallback):
                def on_open(self): pass
                def on_complete(self): done.set()
                def on_error(self, r):
                    print(f"[ASR 错误] {r}")
                    done.set()
                def on_event(self, r: RecognitionResult):
                    if not all_sent.is_set():
                        return
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
            all_sent.set()
            try:
                rec.stop()
            except Exception:
                pass
            done.wait(timeout=15)

            raw = "".join(result_sentences[k] for k in sorted(result_sentences))
            if not raw:
                print("（未识别到内容）")
                return

            print(f"[ASR] {raw}")
            text = polish_text(raw)
            print(f"[输入] {text}")
            type_text(text)

    def start_recording(self):
        with self._record_lock:
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
            print("🎤 录音中…")

    def stop_recording(self):
        with self._record_lock:
            if not self.is_recording:
                return
            self.is_recording = False
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
    ns_app = AppKit.NSApplication.sharedApplication()
    ns_app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    app = SpeechApp()

    def run_keyboard():
        with keyboard.Listener(
            on_press=app._on_press,
            on_release=app._on_release,
        ) as listener:
            listener.join()

    threading.Thread(target=run_keyboard, daemon=True).start()

    print("=" * 42)
    print("  YouSpeak 语音输入  (按住 右⌥ 说话)")
    print("  Ctrl+C 退出")
    print("=" * 42)

    run_loop = Foundation.NSRunLoop.currentRunLoop()
    try:
        while True:
            run_loop.runUntilDate_(Foundation.NSDate.dateWithTimeIntervalSinceNow_(0.1))
    except KeyboardInterrupt:
        print("\n再见！")


if __name__ == "__main__":
    main()
