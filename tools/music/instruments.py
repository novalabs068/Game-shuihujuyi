"""宋代乐器的数学合成（配乐 compose.py 用；音效改用真实录音，见 real_sfx.py）。

都是「加法合成」：一件乐器 = 若干泛音，每个泛音有自己的音量和衰减，再加上起音的噪声、音高的滑动。
弦乐：古琴（低沉、长余音、按弦后走手滑音）、古筝、琵琶（明亮、轮指）。
管乐：洞箫（气声重）、横笛（笛膜的沙沙声）、觱篥（双簧，鼻音重，宋代鼓吹、教坊的主奏）、号角。
打击：大鼓（战鼓）、堂鼓、板鼓、拍板（宋词、教坊打节拍的檀板）、木鱼、钹、大锣、小锣、方响（铁片）、磬、编钟。
只用 numpy；滤波都在频域里做（不需要 scipy）。
"""

import numpy as np

SR = 44100


def t_of(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def rng(seed: float) -> np.random.Generator:
    return np.random.default_rng(int(abs(seed) * 1000) % (2 ** 32))


def spectral(x: np.ndarray, gain) -> np.ndarray:
    """频域滤波：gain(频率数组) 给出每个频率的放大倍数。"""
    n = len(x)
    size = 1 << max(n - 1, 1).bit_length()
    spec = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1 / SR)
    return np.fft.irfft(spec * gain(f), size)[:n]


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return spectral(x, lambda f: 1 / (1 + (lo / np.maximum(f, 1)) ** 4) / (1 + (f / hi) ** 4))


def lowpass(x: np.ndarray, hi: float) -> np.ndarray:
    return spectral(x, lambda f: 1 / (1 + (f / hi) ** 4))


def highpass(x: np.ndarray, lo: float) -> np.ndarray:
    return spectral(x, lambda f: 1 / (1 + (lo / np.maximum(f, 1)) ** 4))


def noise(seconds: float, seed: float = 1) -> np.ndarray:
    return rng(seed).standard_normal(int(SR * seconds))


def phase_of(freq_curve: np.ndarray) -> np.ndarray:
    return 2 * np.pi * np.cumsum(freq_curve) / SR


def slide_curve(t: np.ndarray, semis: float, start: float, length: float) -> np.ndarray:
    """从 start 秒起用 length 秒平滑地滑 semis 个半音（返回频率倍数）。"""
    k = np.clip((t - start) / max(length, 1e-3), 0, 1)
    k = k * k * (3 - 2 * k)
    return 2 ** (semis * k / 12)


def gauss(f, center: float, width: float):
    return np.exp(-((f - center) / width) ** 2)


# --- 弦乐 ---

def plucked(freq: float, length: float, vel: float, pos: float, partials: int, decay0: float, decay_k: float,
            curve: np.ndarray | None = None, bright: float = 1.0, seed: float = 0) -> np.ndarray:
    """拨弦通用模型：拨弦位置 pos 决定哪些泛音弱（|sin(πk·pos)|），高泛音衰减更快。"""
    t = t_of(length)
    fc = freq * (curve if curve is not None else np.ones_like(t))
    out = np.zeros_like(t)
    for k in range(1, partials + 1):
        if freq * k > SR / 2.3:
            break
        amp = abs(np.sin(np.pi * k * pos)) / k ** (1.15 / bright)
        out += amp * np.sin(phase_of(fc * k * (1 + 0.00025 * k * k)) + k) * np.exp(-t * (decay0 + decay_k * k))
    return out * vel * np.minimum(t / 0.002, 1)


def guqin(freq: float, dur: float, vel: float = 1.0, slide: float = 0.0, yin: bool = False) -> np.ndarray:
    """古琴：声音低沉、余音很长；slide 是拨完后左手走手滑几个半音（绰注），yin 是吟（慢而宽的揉弦）。"""
    length = max(dur, 1.2) + 2.0
    t = t_of(length)
    curve = slide_curve(t, slide, min(dur * 0.45, 0.6), min(dur * 0.4, 0.5)) if slide else np.ones_like(t)
    if yin:
        curve = curve * 2 ** (0.18 * np.sin(2 * np.pi * 3.2 * t) * np.clip((t - 0.3) / 0.4, 0, 1) / 12)
    body = plucked(freq, length, 1.0, 0.13, 14, 0.55, 0.42, curve, 0.95, freq)
    # 指肉触弦的一点擦声
    squeak = bandpass(noise(length, freq), 900, 3500) * np.exp(-t * 60) * 0.05
    out = body + squeak
    # 按住的音放开后就收掉
    out *= np.clip((dur + 1.6 - t) / 1.2, 0, 1)
    return out * vel * 0.42


def zheng(freq: float, dur: float = 1.0, vel: float = 1.0, bend: float = 0.0) -> np.ndarray:
    """古筝：比古琴亮，起音带下滑的按音；bend 为右手拨后左手按出的上滑（半音）。"""
    length = max(dur, 1.0) + 1.0
    t = t_of(length)
    curve = (1 + 0.01 * np.exp(-t * 30)) * (slide_curve(t, bend, dur * 0.3, 0.12) if bend else 1)
    out = plucked(freq, length, 1.0, 0.21, 10, 1.4, 1.1, curve, 1.0, freq)
    out += bandpass(noise(length, freq + 1), 1500, 7000) * np.exp(-t * 150) * 0.12
    return out * vel * 0.3


def pipa(freq: float, dur: float = 0.5, vel: float = 1.0, tremolo: bool = False) -> np.ndarray:
    """琵琶：清脆、衰减快；tremolo 为轮指（一秒十五下左右地连弹，力度起伏）。"""
    def one(v: float, seed: float) -> np.ndarray:
        length = 0.9
        t = t_of(length)
        tone = plucked(freq, length, 1.0, 0.11, 16, 3.5, 1.6, None, 1.2, seed)
        click = bandpass(noise(length, seed), 2000, 8000) * np.exp(-t * 300) * 0.25
        return (tone + click) * v

    if not tremolo:
        return one(vel, freq) * 0.3
    n = int(SR * (dur + 0.9))
    out = np.zeros(n)
    step = 1 / 15
    r = rng(freq)
    i = 0
    while i * step < dur:
        s = one(0.55 + 0.35 * r.random(), freq + i)
        a = int(i * step * SR)
        end = min(n, a + len(s))
        out[a:end] += s[: end - a]
        i += 1
    return out * vel * 0.22


# --- 管乐 ---

def _wind_env(t: np.ndarray, dur: float, attack: float, release: float) -> np.ndarray:
    return np.clip(t / attack, 0, 1) * np.clip((dur + release - t) / release, 0, 1)


def xiao(freq: float, dur: float, vel: float = 1.0, scoop: bool = True) -> np.ndarray:
    """洞箫：音色圆而暗，气声很重；音头从下面略微兜上来，长音后段有轻颤。"""
    length = dur + 0.35
    t = t_of(length)
    fc = freq * (slide_curve(t, 0.45, 0, 0.12) * 2 ** (-0.45 / 12) if scoop else 1)
    fc = fc * (1 + 0.004 * np.sin(2 * np.pi * 4.6 * t) * np.clip((t - 0.5) / 0.5, 0, 1))
    ph = phase_of(fc)
    tone = np.sin(ph) + 0.1 * np.sin(2 * ph) + 0.14 * np.sin(3 * ph) + 0.03 * np.sin(5 * ph)
    breath = bandpass(noise(length, freq), freq * 0.9, freq * 5) * 0.55
    env = _wind_env(t, dur, 0.14, 0.25)
    swell = 0.8 + 0.2 * np.sin(np.pi * np.clip(t / max(dur, 0.1), 0, 1))
    return (tone + breath * (0.6 + 0.4 * np.exp(-t * 3))) * env * swell * vel * 0.2


def dizi(freq: float, dur: float, vel: float = 1.0, grace: float = 0.0) -> np.ndarray:
    """横笛：明亮，笛膜振动带出的沙沙高音；grace 为上方倚音（半音数），起音先点一下再落到本音。"""
    length = dur + 0.25
    t = t_of(length)
    fc = np.full_like(t, freq)
    if grace:
        fc = fc * np.where(t < 0.055, 2 ** (grace / 12), 1.0)
    fc = fc * (1 + 0.006 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.35) / 0.3, 0, 1))
    ph = phase_of(fc)
    tone = sum(np.sin(k * ph) / k ** 1.6 for k in range(1, 8))
    buzz = sum(np.sin(k * ph + k * k) for k in range(5, 12)) * 0.022 * (1 + 0.5 * lowpass(noise(length, freq), 60))
    breath = bandpass(noise(length, freq + 3), 2500, 9000) * 0.05
    env = _wind_env(t, dur, 0.035, 0.12)
    return (tone + buzz + breath) * env * vel * 0.16


def bili(freq: float, dur: float, vel: float = 1.0, from_freq: float = 0.0) -> np.ndarray:
    """觱篥：竹管双簧，声音高亢带鼻音（共振峰 1.1k、2.6k），音与音之间常滑过去；宋代鼓吹乐、教坊的领奏。"""
    length = dur + 0.2
    t = t_of(length)
    fc = np.full_like(t, freq)
    if from_freq:
        fc = fc * slide_curve(t, 12 * np.log2(from_freq / freq), 0, 0.0) * slide_curve(t, -12 * np.log2(from_freq / freq), 0, 0.07)
    fc = fc * (1 + 0.011 * np.sin(2 * np.pi * 5.8 * t) * np.clip((t - 0.2) / 0.25, 0, 1))
    ph = phase_of(fc)
    out = np.zeros_like(t)
    for k in range(1, 24):
        f = freq * k
        if f > SR / 2.3:
            break
        amp = (1 / k ** 0.75) * (0.25 + gauss(f, 1150, 380) + 0.6 * gauss(f, 2650, 600))
        out += amp * np.sin(k * ph)
    reed = bandpass(noise(length, freq), 1500, 5000) * 0.04
    env = _wind_env(t, dur, 0.03, 0.08) * (0.85 + 0.15 * np.minimum(t / 0.4, 1))
    return (out + reed) * env * vel * 0.09


def horn(freq: float, dur: float, vel: float = 1.0) -> np.ndarray:
    """号角：低沉的长鸣，先暗后亮（吹足了气泛音才出来），音头略往上兜。"""
    length = dur + 0.5
    t = t_of(length)
    env = np.clip(t / 0.35, 0, 1) ** 1.5 * np.clip((dur + 0.5 - t) / 0.5, 0, 1)
    fc = freq * slide_curve(t, 1.0, 0, 0.2) * 2 ** (-1 / 12)
    fc = fc * (1 + 0.003 * np.sin(2 * np.pi * 4.2 * t))
    ph = phase_of(fc)
    out = np.zeros_like(t)
    for k in range(1, 16):
        out += np.sin(k * ph) * k ** -(2.4 - 1.3 * env)
    return out * env * vel * 0.3


# --- 打击 ---

def dagu(vel: float = 1.0, seed: float = 1) -> np.ndarray:
    """大鼓（战鼓）：鼓腔大，低音长，鼓皮被槌打的「咚」。"""
    t = t_of(1.6)
    f = 56 + 38 * np.exp(-t * 16)
    body = np.sin(phase_of(f)) * np.exp(-t * 3.2) + 0.45 * np.sin(phase_of(f * 1.59)) * np.exp(-t * 7)
    skin = lowpass(noise(1.6, seed), 1400) * np.exp(-t * 28) * 0.9
    stick = bandpass(noise(1.6, seed + 1), 500, 3000) * np.exp(-t * 110) * 0.35
    return (body + skin + stick) * vel * 0.6


def tanggu(vel: float = 1.0, seed: float = 2) -> np.ndarray:
    """堂鼓：比大鼓小，声音紧，「嗵」。"""
    t = t_of(0.7)
    f = 118 + 60 * np.exp(-t * 28)
    body = np.sin(phase_of(f)) * np.exp(-t * 8) + 0.3 * np.sin(phase_of(f * 1.7)) * np.exp(-t * 14)
    skin = bandpass(noise(0.7, seed), 200, 2500) * np.exp(-t * 45) * 0.5
    return (body + skin) * vel * 0.45


def bangu(vel: float = 1.0, seed: float = 3) -> np.ndarray:
    """板鼓（单皮鼓）：又小又硬，「哒」的一声，打快节奏。"""
    t = t_of(0.18)
    body = np.sin(2 * np.pi * 420 * t) * np.exp(-t * 38)
    crack = bandpass(noise(0.18, seed), 1200, 6000) * np.exp(-t * 90)
    return (body * 0.6 + crack * 0.7) * vel * 0.35


def paiban(vel: float = 1.0, seed: float = 4) -> np.ndarray:
    """拍板（檀板）：几片硬木一合，「啪」一声带点木头的鸣响，两片相差几毫秒。"""
    t = t_of(0.25)
    one = np.zeros_like(t)
    for f, d, a in [(1180, 55, 0.7), (1870, 70, 0.5), (2950, 90, 0.35), (4400, 120, 0.2)]:
        one += a * np.sin(2 * np.pi * f * t) * np.exp(-t * d)
    one += bandpass(noise(0.25, seed), 1500, 7000) * np.exp(-t * 160) * 1.2
    one *= np.minimum(t / 0.0006, 1)
    out = one.copy()
    lag = int(SR * 0.006)
    out[lag:] += one[:-lag] * 0.6
    return out * vel * 0.35


def muyu(vel: float = 1.0, pitch: float = 1.0) -> np.ndarray:
    """木鱼：空心木头「笃」。"""
    t = t_of(0.15)
    tone = np.sin(2 * np.pi * 760 * pitch * t) + 0.35 * np.sin(2 * np.pi * 1690 * pitch * t) * np.exp(-t * 30)
    return tone * np.exp(-t * 48) * np.minimum(t / 0.0008, 1) * vel * 0.3


def bo(vel: float = 1.0, open_: bool = True, seed: float = 5) -> np.ndarray:
    """钹（铙钹）：一对铜片相击，满是高频的「嚓」；open_=False 是击后马上捂住（短促的「嚓」）。"""
    length = 2.2 if open_ else 0.25
    t = t_of(length)
    shimmer = np.zeros_like(t)
    r = rng(seed)
    for _ in range(40):
        f = r.uniform(700, 9000)
        shimmer += np.sin(2 * np.pi * f * t + r.uniform(0, 6)) * np.exp(-t * r.uniform(2.0, 5.0)) / 40
    hiss = highpass(noise(length, seed), 3500) * np.exp(-t * (2.2 if open_ else 22))
    out = (shimmer * 3 + hiss * 0.6) * np.minimum(t / 0.001, 1)
    if not open_:
        out *= np.exp(-t * 18)
    return out * vel * 0.4


def daluo(vel: float = 1.0, freq: float = 160) -> np.ndarray:
    """大锣：「哐——」，敲下去以后音高往下沉，嗡很久。"""
    t = t_of(3.2)
    bend = 1 - 0.06 * (1 - np.exp(-t * 3))
    out = np.zeros_like(t)
    for ratio, amp, d in [(1.0, 1.0, 1.0), (1.52, 0.7, 1.4), (2.13, 0.55, 1.9), (2.71, 0.4, 2.4), (3.4, 0.3, 3.0), (4.6, 0.2, 3.6), (6.1, 0.12, 4.5)]:
        out += amp * np.sin(phase_of(freq * ratio * bend)) * np.exp(-t * d)
    strike = bandpass(noise(3.2, freq), 300, 4000) * np.exp(-t * 30) * 0.5
    return (out + strike) * np.minimum(t / 0.003, 1) * vel * 0.35


def xiaoluo(vel: float = 1.0, freq: float = 620) -> np.ndarray:
    """小锣：「台」，敲下去音高往上翘。"""
    t = t_of(1.2)
    bend = 1 + 0.09 * (1 - np.exp(-t * 9))
    out = np.zeros_like(t)
    for ratio, amp, d in [(1.0, 1.0, 3.0), (1.8, 0.35, 5), (2.9, 0.2, 7)]:
        out += amp * np.sin(phase_of(freq * ratio * bend)) * np.exp(-t * d)
    return out * np.minimum(t / 0.002, 1) * vel * 0.3


def fangxiang(freq: float, vel: float = 1.0, seconds: float = 1.6) -> np.ndarray:
    """方响：十六块铁片挂在架上用小槌敲，宋代教坊常用；声音清亮，余音中等。"""
    t = t_of(seconds)
    out = np.zeros_like(t)
    for ratio, amp, d in [(1.0, 1.0, 2.4), (2.78, 0.35, 5), (5.2, 0.16, 9), (8.3, 0.06, 14)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * d)
    tick = bandpass(noise(seconds, freq), 3000, 9000) * np.exp(-t * 200) * 0.15
    return (out + tick) * np.minimum(t / 0.001, 1) * vel * 0.3


def qing(freq: float, vel: float = 1.0, seconds: float = 3.0) -> np.ndarray:
    """磬：石片，声音温润、余音长，泛音不成整数倍。"""
    t = t_of(seconds)
    out = np.zeros_like(t)
    for ratio, amp, d in [(1.0, 1.0, 1.1), (2.32, 0.45, 2.2), (3.95, 0.22, 3.5), (5.6, 0.1, 5)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * d)
    return out * np.minimum(t / 0.002, 1) * vel * 0.35


def bianzhong(freq: float, vel: float = 1.0, seconds: float = 3.0) -> np.ndarray:
    """编钟：铜钟一击两音（正鼓音和侧鼓音差小三度），浑厚庄重。"""
    t = t_of(seconds)
    out = np.zeros_like(t)
    for ratio, amp, d in [(1.0, 1.0, 1.0), (1.19, 0.6, 1.3), (2.0, 0.3, 2.2), (2.66, 0.35, 2.8), (3.9, 0.15, 4.5), (5.4, 0.08, 6)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * t + ratio) * np.exp(-t * d)
    strike = bandpass(noise(seconds, freq), 800, 5000) * np.exp(-t * 80) * 0.2
    return (out + strike) * np.minimum(t / 0.002, 1) * vel * 0.32


def wind(seconds: float, seed: float = 9) -> np.ndarray:
    """山野的风声：低沉的噪声，强弱和音色都缓缓起伏。"""
    t = t_of(seconds)
    base = bandpass(noise(seconds, seed), 120, 900)
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * t / 11 + 1) * np.sin(2 * np.pi * t / 4.3)
    whistle = bandpass(noise(seconds, seed + 1), 700, 1600) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 7.7)) ** 3 * 0.4
    return (base * (0.4 + 0.6 * gust) + whistle) * 0.12


# --- 空间 ---

def reverb_stereo(left: np.ndarray, right: np.ndarray, seconds: float = 2.2, wet: float = 0.25, dark: float = 5000) -> tuple:
    """立体声混响：左右各用一段不同的衰减噪声做卷积（越往后越暗），前面加 25 毫秒的预延迟。"""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    pre = int(SR * 0.025)
    outs = []
    for seed, x in [(71, left), (72, right)]:
        ir = rng(seed).standard_normal(n) * np.exp(-t * 6.9 / seconds)
        ir = lowpass(ir, dark)
        ir = np.concatenate([np.zeros(pre), ir])
        ir /= np.sqrt(np.sum(ir ** 2))
        size = len(x) + len(ir)
        fft = 1 << (size - 1).bit_length()
        w = np.fft.irfft(np.fft.rfft(x, fft) * np.fft.rfft(ir, fft), fft)[:size]
        out = np.zeros(size)
        out[: len(x)] += x
        outs.append(out + w * wet)
    return outs[0], outs[1]
