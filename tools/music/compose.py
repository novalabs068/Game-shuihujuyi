"""用程序作曲：合成 5 首古风循环配乐（原创，没有版权问题）。

    python tools/music/compose.py [曲名 ...]      # 默认全部生成，输出 audio/music/<曲名>.ogg

乐器全部用数学合成：古筝（拨弦，泛音各自衰减）、笛子（带颤音和气声）、低音（古琴般的长音）、
大鼓、木鱼，最后加一点混响。旋律在五声音阶里按「主题 → 变奏 → 对比 → 再现」生成，结尾回到主音，
首尾无缝循环。同一个随机种子每次生成的曲子都一样，想换一版就改 TRACKS 里的 seed。
需要 numpy，转 ogg 需要 ffmpeg（带 libvorbis）。
"""

import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "audio" / "music"

# 五声音阶（半音数）：宫调明亮，羽调阴沉
GONG = [0, 2, 4, 7, 9]
YU = [0, 3, 5, 7, 10]

TRACKS = {
    # 名字: 速度、小节数、调式、主音频率、种子、风格
    "jianghu": dict(bpm=72, bars=32, mode=GONG, tonic=293.66, seed=11, style="calm"),
    "jieshi": dict(bpm=100, bars=32, mode=GONG, tonic=329.63, seed=23, style="lively"),
    "jiaoye": dict(bpm=66, bars=24, mode=YU, tonic=246.94, seed=37, style="dark"),
    "zhandou": dict(bpm=132, bars=32, mode=YU, tonic=220.00, seed=41, style="battle"),
    "liezhuan": dict(bpm=60, bars=24, mode=YU, tonic=261.63, seed=53, style="story"),
}


# --- 乐器 ---

def env_exp(n: int, rate: float) -> np.ndarray:
    return np.exp(-np.arange(n) / SR * rate)


def zheng(freq: float, dur: float = 1.5, vel: float = 1.0) -> np.ndarray:
    """古筝拨一下：泛音越高衰减越快，起音带一点拨弦的噪声和下滑的按音。"""
    length = max(dur, 1.6) + 0.6
    n = int(SR * length)
    t = np.arange(n) / SR
    bend = 1.0 + 0.012 * np.exp(-t * 30)
    out = np.zeros(n)
    for k in range(1, 9):
        f = freq * k * (1 + 0.0004 * k * k)
        if f > SR / 2.2:
            break
        out += np.sin(2 * np.pi * f * np.cumsum(bend) / SR) / k ** 1.3 * env_exp(n, 1.8 + 1.4 * k)
    attack = np.minimum(t / 0.003, 1.0)
    noise = np.random.default_rng(int(freq * 10)).standard_normal(n) * np.exp(-t * 120) * 0.15
    return (out * attack + noise) * vel * 0.32


def flute(freq: float, dur: float, vel: float = 1.0) -> np.ndarray:
    """笛子：基音为主，加一点二三次泛音，起音慢，长音时有颤音，带一丝气声。"""
    n = int(SR * (dur + 0.2))
    t = np.arange(n) / SR
    vib = 1 + 0.005 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    phase = 2 * np.pi * freq * np.cumsum(vib) / SR
    tone = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.07 * np.sin(3 * phase)
    breath = np.convolve(np.random.default_rng(int(freq)).standard_normal(n), np.ones(12) / 12, "same") * 0.06
    attack = np.clip(t / 0.07, 0, 1)
    release = np.clip((dur + 0.2 - t) / 0.18, 0, 1)
    return (tone + breath) * attack * release * vel * 0.2


def bass(freq: float, dur: float, vel: float = 1.0) -> np.ndarray:
    """低音：像古琴的长音，慢慢衰减。"""
    n = int(SR * (dur + 1.0))
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(4 * np.pi * freq * t) * np.exp(-t * 3)
    return tone * np.minimum(t / 0.01, 1) * np.exp(-t * 1.3) * vel * 0.3


def drum(vel: float = 1.0) -> np.ndarray:
    """大鼓：音高从高往低一扫，加一点鼓皮的噪声。"""
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    f = 55 + 70 * np.exp(-t * 25)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    hit = np.random.default_rng(1).standard_normal(n) * np.exp(-t * 60) * 0.3
    return (body + hit) * vel * 0.55


def block(vel: float = 1.0) -> np.ndarray:
    """木鱼：很短的一声「笃」。"""
    n = int(SR * 0.12)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 820 * t) + 0.4 * np.sin(2 * np.pi * 1740 * t)) * np.exp(-t * 55) * vel * 0.22


def reverb(x: np.ndarray, seconds: float = 1.8, wet: float = 0.22) -> np.ndarray:
    """简单混响：和一段指数衰减的噪声做卷积。"""
    n = int(SR * seconds)
    ir = np.random.default_rng(7).standard_normal(n) * np.exp(-np.arange(n) / SR * 3.2)
    ir = np.convolve(ir, np.ones(30) / 30, "same")
    ir /= np.sqrt(np.sum(ir ** 2))
    size = len(x) + n
    fft = 1 << (size - 1).bit_length()
    wet_sig = np.fft.irfft(np.fft.rfft(x, fft) * np.fft.rfft(ir, fft), fft)[:size]
    out = np.zeros(size)
    out[: len(x)] += x
    return out + wet_sig * wet


# --- 作曲 ---

class Song:
    def __init__(self, bpm: int, bars: int, mode: list, tonic: float, seed: int, style: str):
        self.beat = 60.0 / bpm
        self.bars = bars
        self.mode = mode
        self.tonic = tonic
        self.rng = np.random.default_rng(seed)
        self.style = style
        self.length = bars * 4 * self.beat
        self.buf = np.zeros(int(SR * (self.length + 4)))

    def pitch(self, degree: int, octave: int = 0) -> float:
        """五声音阶第 degree 个音（可以超过 5，自动升八度）。"""
        o, d = divmod(degree, 5)
        semis = self.mode[d] + 12 * (o + octave)
        return self.tonic * 2 ** (semis / 12)

    def add(self, sound: np.ndarray, at_beat: float, gain: float = 1.0) -> None:
        i = int(at_beat * self.beat * SR)
        end = min(len(self.buf), i + len(sound))
        self.buf[i:end] += sound[: end - i] * gain

    # 旋律：2 小节的动机，按 A A' B A'' 组成 8 小节一句
    def motif(self, start: int) -> list:
        rhythms = {
            "calm": [[2, 1, 1], [1.5, 0.5, 2], [1, 1, 2], [3, 1]],
            "lively": [[1, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 2], [1, 1, 0.5, 0.5, 1]],
            "dark": [[3, 1], [2, 2], [1.5, 0.5, 2]],
            "battle": [[0.5, 0.5, 1, 0.5, 0.5, 1], [1, 0.5, 0.5, 2], [0.5, 0.5, 0.5, 0.5, 2]],
            "story": [[3, 1], [2, 1, 1], [4]],
        }[self.style]
        notes = []
        degree = start
        for bar in range(2):
            for d in rhythms[self.rng.integers(len(rhythms))]:
                degree = int(np.clip(degree + self.rng.choice([-2, -1, -1, 0, 1, 1, 2]), 2, 9))
                notes.append([degree, d])
        return notes

    def vary(self, notes: list) -> list:
        out = [list(n) for n in notes]
        for n in out[-3:]:
            n[0] = int(np.clip(n[0] + self.rng.choice([-1, 0, 1]), 2, 9))
        return out

    def melody(self) -> list:
        a = self.motif(5)
        b = self.motif(7)
        phrase = a + self.vary(a) + b + self.vary(a)
        song = []
        for i in range(self.bars // 8):
            song += phrase if i % 2 == 0 else self.vary(phrase)
        song[-1][0] = 5  # 结尾落在主音
        return song

    def render(self) -> np.ndarray:
        lead = flute if self.style in ("calm", "dark", "story") else zheng
        beat = 0.0
        for degree, d in self.melody():
            if self.style == "story" and self.rng.random() < 0.12:
                beat += d  # 抒情曲留一点空白
                continue
            self.add(lead(self.pitch(degree), d * self.beat * 0.95), beat, 1.0 if lead is flute else 0.9)
            beat += d
        # 和声根音走向：宫 羽 徵 宫 / 羽调时 羽 角 商 羽（都用音阶序号表示）
        roots = [0, 4, 3, 0] if self.mode is GONG else [0, 2, 1, 0]
        for bar in range(self.bars):
            root = roots[(bar // 2) % 4]
            b0 = bar * 4
            self.add(bass(self.pitch(root, -1), 4 * self.beat), b0, 0.9)
            if self.style == "calm":
                for i, step in enumerate([0, 2, 5, 2]):
                    self.add(zheng(self.pitch(root + step)), b0 + i, 0.45)
            elif self.style == "lively":
                for i, step in enumerate([0, 2, 3, 5, 3, 2, 5, 7]):
                    self.add(zheng(self.pitch(root + step)), b0 + i * 0.5, 0.35)
                for i in range(4):
                    self.add(block(1.0 if i % 2 == 0 else 0.6), b0 + i)
                self.add(drum(0.5), b0)
            elif self.style == "dark":
                self.add(zheng(self.pitch(root)), b0, 0.5)
                self.add(zheng(self.pitch(root + 2)), b0 + 2.5, 0.35)
                if bar % 2 == 1:
                    self.add(drum(0.35), b0 + 3)
            elif self.style == "battle":
                for i in range(8):
                    step = [0, 0, 2, 0, 3, 0, 2, 5][i]
                    self.add(zheng(self.pitch(root + step, -1), 0.3), b0 + i * 0.5, 0.4)
                for i in [0, 1.5, 2, 3, 3.5]:
                    self.add(drum(1.0 if i in (0, 2) else 0.6), b0 + i)
                self.add(block(0.8), b0 + 1)
                self.add(block(0.8), b0 + 3)
            elif self.style == "story":
                if bar % 2 == 0:
                    for i, step in enumerate([0, 5, 7]):
                        self.add(zheng(self.pitch(root + step)), b0 + i * 1.5, 0.3)
        wet = reverb(self.buf, wet=0.3 if self.style in ("calm", "story", "dark") else 0.18)
        # 首尾无缝：把超出曲长的尾音叠回开头
        n = int(self.length * SR)
        loop = wet[:n].copy()
        tail = wet[n:]
        loop[: len(tail)] += tail[: n]
        loop /= np.max(np.abs(loop)) / 0.89
        return loop


def write_ogg(samples: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wav = path.with_suffix(".wav")
    # 微微的立体声：右声道晚 9 毫秒
    delay = int(SR * 0.009)
    left = samples
    right = np.concatenate([samples[-delay:], samples[:-delay]])
    stereo = np.stack([left, right], axis=1)
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((stereo * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "3", str(path)], check=True)
    wav.unlink()


def main() -> None:
    names = sys.argv[1:] or list(TRACKS)
    for name in names:
        song = Song(**TRACKS[name])
        samples = song.render()
        out = OUT / f"{name}.ogg"
        write_ogg(samples, out)
        print(f"{name}: {len(samples) / SR:.0f} 秒 → {out.relative_to(ROOT)}（{out.stat().st_size // 1024} KB）")


if __name__ == "__main__":
    main()
