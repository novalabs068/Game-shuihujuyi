"""用程序合成音效（原创，没有版权问题）。

    python tools/music/make_sfx.py [名字 ...]     # 默认全部生成，输出 audio/sfx/<名字>.ogg

招募：令牌呼啸、大鼓「咚」、纸片轻落、翻牌、上扬的铃音、铜锣。
战斗：箭矢破空、放绝招的鼓点、胜利的锣鼓。界面：木鱼一声。
刀剑、重击、拳脚、暴击这些命中声用真实录音叠，见 real_sfx.py。
乐器函数借 compose.py 的大鼓、木鱼和混响。需要 numpy、ffmpeg（带 libvorbis）。
"""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compose import SR, block, drum, reverb, write_ogg  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "audio" / "sfx"
RNG = np.random.default_rng(5)


def t_of(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def noise(seconds: float) -> np.ndarray:
    return RNG.standard_normal(int(SR * seconds))


def lowpass(x: np.ndarray, k: int) -> np.ndarray:
    return np.convolve(x, np.ones(k) / k, "same")


def highpass(x: np.ndarray, k: int) -> np.ndarray:
    return x - lowpass(x, k)


def bandsweep(x: np.ndarray, start: int, end: int) -> np.ndarray:
    """噪声的「音色」从 start 扫到 end（用分段平滑模拟带通的移动）。"""
    out = np.zeros_like(x)
    seg = len(x) // 24
    for i in range(24):
        k = int(start + (end - start) * i / 23)
        a, b = i * seg, (i + 1) * seg if i < 23 else len(x)
        out[a:b] = highpass(lowpass(x, max(k, 1)), max(k * 4, 2))[a:b]
    return out


def bell(freq: float, seconds: float, decay: float) -> np.ndarray:
    """铃：几个不成整数倍的泛音，敲一下慢慢衰减。"""
    t = t_of(seconds)
    out = np.zeros_like(t)
    for ratio, amp in [(1.0, 1.0), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay * ratio ** 0.5)
    return out * np.minimum(t / 0.002, 1)


def gong(seconds: float = 2.6) -> np.ndarray:
    """铜锣：一大堆不和谐的泛音，音高先略往上走，再长长地嗡下去。"""
    t = t_of(seconds)
    bend = 1 + 0.03 * (1 - np.exp(-t * 6))
    out = np.zeros_like(t)
    for ratio, amp in [(1.0, 1.0), (1.47, 0.7), (2.09, 0.6), (2.56, 0.45), (3.14, 0.35), (4.2, 0.25), (5.9, 0.15)]:
        f = 180 * ratio
        out += amp * np.sin(2 * np.pi * f * np.cumsum(bend) / SR) * np.exp(-t * (1.4 + ratio * 0.5))
    strike = highpass(noise(seconds), 6) * np.exp(-t * 40) * 0.6
    return (out + strike) * np.minimum(t / 0.004, 1)


def pad(x: np.ndarray, seconds: float) -> np.ndarray:
    n = int(SR * seconds)
    return np.concatenate([x, np.zeros(max(n - len(x), 0))])


def mixdown(*parts: tuple) -> np.ndarray:
    """把几段声音按起点（秒）叠在一起。"""
    end = max(int(start * SR) + len(x) for start, x in parts)
    out = np.zeros(end)
    for start, x in parts:
        i = int(start * SR)
        out[i:i + len(x)] += x
    return out


def normalize(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def token_whoosh() -> np.ndarray:
    t = t_of(0.6)
    swell = np.sin(np.pi * np.minimum(t / 0.6, 1)) ** 1.5
    return bandsweep(noise(0.6), 40, 4) * swell * 0.9


def token_slam() -> np.ndarray:
    low = drum(1.0)
    t = t_of(1.2)
    sub = np.sin(2 * np.pi * np.cumsum(40 + 30 * np.exp(-t * 12)) / SR) * np.exp(-t * 4)
    return reverb(mixdown((0, low * 1.4), (0, sub)), 1.4, 0.3)


def card_drop() -> np.ndarray:
    t = t_of(0.1)
    tap = highpass(noise(0.1), 8) * np.exp(-t * 90) * 0.5
    thump = np.sin(2 * np.pi * 110 * t) * np.exp(-t * 50) * 0.5
    return tap + thump


def card_flip() -> np.ndarray:
    t = t_of(0.08)
    flick = highpass(noise(0.08), 3) * np.exp(-t * 70)
    return mixdown((0, flick * 0.6), (0.045, flick * 0.4))


def rare_shimmer() -> np.ndarray:
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
    parts = [(i * 0.09, bell(f, 0.9, 5) * 0.4) for i, f in enumerate(notes)]
    return reverb(mixdown(*parts), 1.2, 0.35)


def jia_gong() -> np.ndarray:
    return reverb(gong(2.8), 1.8, 0.3)


def arrow() -> np.ndarray:
    t = t_of(0.22)
    swell = np.sin(np.pi * t / 0.22)
    return bandsweep(noise(0.22), 2, 8) * swell * 0.7


def skill_drum() -> np.ndarray:
    hits = [(0.0, drum(0.8)), (0.12, drum(0.8)), (0.24, drum(1.2))]
    return reverb(mixdown(*hits), 1.0, 0.25)


def victory() -> np.ndarray:
    drums = [(i * 0.14, drum(0.9)) for i in range(4)]
    return reverb(mixdown(*drums, (0.56, gong(2.4) * 0.8)), 1.6, 0.28)


def ui_click() -> np.ndarray:
    return block(1.0)


SOUNDS = {
    "token_whoosh": token_whoosh, "token_slam": token_slam, "card_drop": card_drop, "card_flip": card_flip,
    "rare_shimmer": rare_shimmer, "jia_gong": jia_gong,
    "arrow": arrow, "skill_drum": skill_drum, "victory": victory, "ui_click": ui_click,
}


def main() -> None:
    names = sys.argv[1:] or list(SOUNDS)
    for name in names:
        samples = normalize(pad(SOUNDS[name](), 0.05))
        # 头尾各淡一下，免得「啪」一声
        fade = min(len(samples) // 10, int(SR * 0.02))
        samples[-fade:] *= np.linspace(1, 0, fade)
        write_ogg(samples, OUT / f"{name}.ogg")
        print(f"audio/sfx/{name}.ogg  {len(samples) / SR:.2f}s")


if __name__ == "__main__":
    main()
