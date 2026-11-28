"""程序作曲：宋代风格的循环配乐（原创，没有版权问题）。

    python3 tools/music/compose.py [曲名 ...]      # 默认生成四首非战斗曲，输出 audio/music/<曲名>.ogg
    python3 tools/music/compose.py --out=目录 zhandou_1   # 合成版战斗曲（还没定用不用，游戏里仍是真录音）

曲风照宋代音乐来：
- 旋律是手写的简谱（见 SCORES），按宋词「上片、下片」的长短句来写，每句落在长音上，句尾檀板「啪」一声；
  调式用五声音阶（宫、商、羽、徵调），偶尔经过清角、变宫。
- 伴奏不用西洋和弦，用中国乐队的「支声」：伴奏乐器跟着旋律走、简化或加花，再加古琴低音长鸣。
- 乐器：古琴、洞箫、横笛、古筝、琵琶、觱篥（宋代鼓吹、教坊的领奏）、号角、战鼓、堂鼓、板鼓、拍板、钹、锣、方响、磬。
  合成方法见 instruments.py。
- 战斗配乐按宋军「鼓吹」：号角、战鼓起头，觱篥、琵琶、笛子领奏，铙钹点重拍。
同一份谱每次生成的曲子都一样（随机数只用来做轻微的快慢、强弱起伏，种子固定）。
响度统一用 ffmpeg 的 EBU R128 量，安静的曲子 -15 LUFS、战斗 -13.5 LUFS。需要 numpy、ffmpeg（带 libvorbis）。
"""

import re
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import instruments as ins  # noqa: E402
from instruments import SR  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "audio" / "music"

# 简谱音级 → 半音数（1=宫 2=商 3=角 4=清角 5=徵 6=羽 7=变宫）
DEGREE = {"1": 0, "2": 2, "3": 4, "4": 5, "5": 7, "6": 9, "7": 11}
PENTA = [0, 2, 4, 7, 9]

# 简谱：「音级:拍数」，音级后面 ' 高八度、, 低八度，0 是休止。一句 8 拍（两小节）。
SCORES = {
    # 大地图：宫调，开阔从容，横笛领奏、古筝支声、古琴低音
    "jianghu": {
        "A1": "3:1.5 5:0.5 6:1 1':1 6:1 5:0.5 3:0.5 5:2",
        "A2": "2:1.5 3:0.5 5:1 3:1 2:0.5 3:0.5 1:1 2:2",
        "A3": "5:1 5:0.5 6:0.5 1':1 2':1 3':1.5 2':0.5 1':1 6:1",
        "A4": "5:1.5 6:0.5 5:1 3:1 2:1 3:0.5 2:0.5 1:2",
        "B1": "6,:1.5 1:0.5 2:1 3:1 5:1 3:1 2:2",
        "B2": "3:1 2:0.5 1:0.5 6,:1 5,:1 6,:1 1:1 6,:2",
        "B3": "1:1 2:1 3:0.5 5:0.5 6:1 5:1.5 6:0.5 3:1 5:1",
        "B4": "6:1 5:0.5 3:0.5 2:1 3:1 2:1 1:0.5 6,:0.5 1:2",
    },
    # 城镇街市：宫调，瓦舍勾栏的热闹，笛子、琵琶、檀板、板鼓
    "jieshi": {
        "A1": "5:0.5 6:0.5 5:0.5 3:0.5 2:1 3:1 5:0.5 5:0.5 6:0.5 1':0.5 6:1 5:1",
        "A2": "3:0.5 5:0.5 2:0.5 3:0.5 1:1 6,:1 1:0.5 2:0.5 3:0.5 5:0.5 2:2",
        "A3": "6:0.5 1':0.5 6:0.5 5:0.5 3:1 5:1 6:1 1':0.5 2':0.5 1':2",
        "A4": "6:0.5 5:0.5 3:0.5 5:0.5 2:0.5 3:0.5 2:0.5 1:0.5 6,:0.5 1:0.5 2:0.5 3:0.5 1:2",
        "B1": "1':1 6:0.5 1':0.5 5:1 6:1 3:0.5 5:0.5 6:0.5 5:0.5 3:2",
        "B2": "2:0.5 3:0.5 5:0.5 3:0.5 2:1 1:1 6,:0.5 1:0.5 2:1 5,:2",
        "B3": "5,:0.5 6,:0.5 1:0.5 2:0.5 3:1 5:1 6:0.5 5:0.5 6:0.5 1':0.5 2':2",
        "B4": "1':0.5 6:0.5 5:0.5 6:0.5 3:0.5 5:0.5 2:0.5 3:0.5 5:0.5 3:0.5 2:0.5 3:0.5 1:2",
    },
    # 郊野、山道：羽调，冷清，洞箫独吹、古琴应和、山风
    "jiaoye": {
        "A1": "6,:2 1:1 2:1 3:3 2:0.5 1:0.5",
        "A2": "2:1.5 3:0.5 1:1 6,:1 5,:4",
        "A3": "3:1 5:1 6:1.5 5:0.5 3:1 2:1 3:2",
        "A4": "5:1 3:0.5 2:0.5 1:1 2:1 6,:4",
        "B1": "6:2 5:1 6:1 1':2 6:1 5:1",
        "B2": "3:1.5 5:0.5 6:1 5:1 3:4",
        "B3": "2:1 3:1 5:1.5 3:0.5 2:1 1:1 6,:2",
        "B4": "1:1.5 2:0.5 3:1 2:0.5 1:0.5 6,:4",
    },
    # 列传（讲故事）：商调，像宋词清唱，古琴领奏、洞箫衬着
    "liezhuan": {
        "A1": "2:2 3:1 5:1 6:1.5 5:0.5 3:2",
        "A2": "5:1 3:1 2:1 1:1 2:4",
        "A3": "5:1.5 6:0.5 1':1 6:1 5:1 6:0.5 5:0.5 3:2",
        "A4": "2:1 3:0.5 5:0.5 3:1 1:1 6,:1 1:1 2:2",
        "B1": "6:2 1':1 2':1 1':1.5 6:0.5 5:2",
        "B2": "3:1 5:1 6:1 5:1 3:1 2:1 1:2",
        "B3": "6,:1 1:1 2:1.5 3:0.5 5:3 3:1",
        "B4": "2:1 1:0.5 6,:0.5 1:1 3:1 2:4",
    },
    # 战斗一：羽调，觱篥领奏，战鼓、堂鼓、铙钹，「鼓角争鸣」
    "zhandou_1": {
        "A1": "6,:0.5 6,:0.5 1:0.5 2:0.5 3:1 3:1 5:0.5 3:0.5 2:0.5 3:0.5 6,:2",
        "A2": "6,:0.5 6,:0.5 1:0.5 2:0.5 3:1 5:1 6:0.5 5:0.5 3:0.5 5:0.5 6:2",
        "A3": "1':1 6:0.5 5:0.5 6:1 3:1 5:0.5 6:0.5 5:0.5 3:0.5 2:2",
        "A4": "3:0.5 2:0.5 1:0.5 2:0.5 3:0.5 5:0.5 3:0.5 2:0.5 1:0.5 2:0.5 6,:1 6,:2",
        "B1": "3':1.5 2':0.5 1':1 6:1 1':1.5 6:0.5 5:2",
        "B2": "6:1 5:0.5 3:0.5 5:1 6:1 3:0.5 2:0.5 1:0.5 2:0.5 3:2",
        "B3": "3':1.5 2':0.5 1':1 2':1 3':1 5':1 3':2",
        "B4": "2':0.5 1':0.5 6:0.5 5:0.5 6:0.5 1':0.5 6:0.5 5:0.5 3:0.5 5:0.5 6:1 6:2",
    },
    # 战斗二：商调，琵琶轮指领奏、笛子接应，紧张的伏兵感
    "zhandou_2": {
        "A1": "2:1 2:0.5 3:0.5 5:1 3:1 2:0.5 1:0.5 6,:0.5 1:0.5 2:2",
        "A2": "5:1 5:0.5 6:0.5 1':1 6:1 5:0.5 3:0.5 2:0.5 3:0.5 5:2",
        "A3": "6:0.5 5:0.5 6:0.5 1':0.5 2':1 1':1 6:0.5 1':0.5 6:0.5 5:0.5 3:2",
        "A4": "2:0.5 3:0.5 5:0.5 3:0.5 2:0.5 1:0.5 6,:0.5 1:0.5 2:1 5,:1 2:2",
        "B1": "5,:0.5 5,:0.5 6,:0.5 1:0.5 2:1 2:1 3:0.5 2:0.5 1:0.5 6,:0.5 5,:2",
        "B2": "6,:0.5 1:0.5 2:0.5 3:0.5 5:1 6:1 5:0.5 3:0.5 5:0.5 6:0.5 1':2",
        "B3": "2':1 1':0.5 6:0.5 5:1 6:1 1':0.5 6:0.5 5:0.5 3:0.5 2:2",
        "B4": "2:0.5 3:0.5 5:0.5 3:0.5 2:0.5 1:0.5 6,:0.5 1:0.5 2:1 5,:1 2:2",
    },
    # 战斗三：徵调，横笛领奏，战鼓踏步，冲锋陷阵
    "zhandou_3": {
        "A1": "5,:0.5 1:0.5 2:0.5 3:0.5 5:1 5:1 6:0.5 5:0.5 3:0.5 2:0.5 3:1 5,:1",
        "A2": "5,:0.5 1:0.5 2:0.5 3:0.5 5:1 6:1 1':0.5 6:0.5 5:0.5 3:0.5 5:2",
        "A3": "1':1 1':0.5 2':0.5 3':1 2':1 1':0.5 6:0.5 5:0.5 6:0.5 1':2",
        "A4": "6:0.5 5:0.5 3:0.5 5:0.5 6:0.5 5:0.5 3:0.5 2:0.5 1:0.5 2:0.5 3:1 5:2",
        "B1": "3:1 5:1 6:1 5:1 3:0.5 2:0.5 1:1 2:2",
        "B2": "3:1 5:1 6:0.5 1':0.5 6:1 5:0.5 6:0.5 3:1 5:2",
        "B3": "6:0.5 6:0.5 1':1 6:0.5 6:0.5 5:1 3:0.5 5:0.5 6:1 6:2",
        "B4": "6:0.5 5:0.5 3:0.5 5:0.5 6:0.5 5:0.5 3:0.5 2:0.5 1:0.5 2:0.5 3:1 5:2",
    },
}

A = ["A1", "A2", "A3", "A4"]
B = ["B1", "B2", "B3", "B4"]
# 曲式：(句子列表, 是否加花变奏)；home 是调式主音（简谱音级），key 是简谱「1」的频率
TRACKS = {
    "jianghu": dict(bpm=72, key=293.66, home="1", form=[(A, False), (B, False), (A, True)], style="jianghu", lufs=-15),
    "jieshi": dict(bpm=100, key=329.63, home="1", form=[(A, False), (B, False), (A, True), (B, True)], style="jieshi", lufs=-15),
    "jiaoye": dict(bpm=62, key=293.66, home="6", form=[(A, False), (B, False), (A, True)], style="jiaoye", lufs=-16),
    "liezhuan": dict(bpm=58, key=261.63, home="2", form=[(A, False), (B, False), (A, True)], style="liezhuan", lufs=-16),
    "zhandou_1": dict(bpm=132, key=261.63, home="6", form=[(A, False), (B, False), (A, True), (B, True)], style="z1", lufs=-13.5, intro=4),
    "zhandou_2": dict(bpm=120, key=246.94, home="2", form=[(A, False), (B, False), (A, True), (B, True)], style="z2", lufs=-13.5, intro=2),
    "zhandou_3": dict(bpm=144, key=293.66, home="5", form=[(A, False), (B, False), (A, True), (B, True)], style="z3", lufs=-13.5, intro=4),
}


def parse(line: str) -> list:
    """简谱一句 → [(半音数或 None, 拍数)]。"""
    out = []
    for tok in line.split():
        m = re.fullmatch(r"([0-7])([',]*):([\d.]+)", tok)
        assert m, tok
        deg, marks, dur = m.groups()
        semi = None if deg == "0" else DEGREE[deg] + 12 * (marks.count("'") - marks.count(","))
        out.append((semi, float(dur)))
    assert abs(sum(d for _, d in out) - 8) < 1e-6, f"一句不是 8 拍：{line}"
    return out


def penta_step(semi: int, step: int) -> int:
    """五声音阶里往上（step>0）或往下走 step 个音。"""
    octave, pc = divmod(semi, 12)
    idx = min(range(5), key=lambda i: abs(PENTA[i] - pc))
    idx += step
    o, i = divmod(idx, 5)
    return PENTA[i] + 12 * (octave + o)


class Song:
    def __init__(self, bpm: int, key: float, home: str, form: list, style: str, lufs: float, intro: int = 0):
        self.beat = 60.0 / bpm
        self.key = key
        self.home = DEGREE[home]
        self.style = style
        self.lufs = lufs
        self.intro = intro * 4  # 拍数
        self.score = SCORES_BY_STYLE[style]
        self.form = form
        self.r = np.random.default_rng(sum(map(ord, style)))
        bars = intro + sum(len(lines) * 2 for lines, _ in form)
        self.length_beats = bars * 4
        self.length = self.length_beats * self.beat
        n = int(SR * (self.length + 8))
        self.L = np.zeros(n)
        self.R = np.zeros(n)

    def hz(self, semi: int) -> float:
        return self.key * 2 ** (semi / 12)

    def add(self, sound: np.ndarray, at_beat: float, gain: float = 1.0, pan: float = 0.0, humanize: bool = True) -> None:
        if humanize:
            at_beat += self.r.normal(0, 0.008) / self.beat
            gain *= 1 + self.r.normal(0, 0.06)
        i = max(int(at_beat * self.beat * SR), 0)
        end = min(len(self.L), i + len(sound))
        a = np.pi / 4 * (pan + 1)
        self.L[i:end] += sound[: end - i] * gain * np.cos(a) * np.sqrt(2)
        self.R[i:end] += sound[: end - i] * gain * np.sin(a) * np.sqrt(2)

    # --- 旋律 ---

    def flowers(self, notes: list) -> list:
        """加花：把一部分一拍的音拆成「本音-上邻音-本音」，句尾长音不动。"""
        out = []
        for i, (semi, d) in enumerate(notes):
            last = i == len(notes) - 1
            if semi is not None and not last and d == 1 and self.r.random() < 0.4:
                out += [(semi, 0.5), (penta_step(semi, 1), 0.25), (semi, 0.25)]
            elif semi is not None and not last and d == 1.5 and self.r.random() < 0.4:
                out += [(semi, 1.0), (penta_step(semi, -1), 0.5)]
            else:
                out.append((semi, d))
        return out

    def melody(self) -> list:
        """整首的旋律：[(起拍, 半音数, 拍数, 句号, 是否句尾, 段落号)]。"""
        notes = []
        beat = self.intro
        line_no = 0
        for section, (lines, vary) in enumerate(self.form):
            for name in lines:
                ns = parse(self.score[name])
                if vary:
                    ns = self.flowers(ns)
                for j, (semi, d) in enumerate(ns):
                    if semi is not None:
                        notes.append((beat, semi, d, line_no, j == len(ns) - 1, section))
                    beat += d
                line_no += 1
        return notes

    # --- 编配 ---

    def render(self) -> tuple:
        mel = self.melody()
        getattr(self, "arr_" + self.style)(mel)
        L, R = self.mix_space()
        # 首尾无缝：把超出曲长的尾音叠回开头
        n = int(self.length * SR)
        out = []
        for ch in (L, R):
            loop = ch[:n].copy()
            tail = ch[n:]
            loop[: min(len(tail), n)] += tail[:n]
            out.append(loop)
        return out[0], out[1]

    def mix_space(self) -> tuple:
        wet = {"jianghu": 0.32, "jieshi": 0.2, "jiaoye": 0.4, "liezhuan": 0.38}.get(self.style, 0.18)
        secs = {"jiaoye": 3.2, "liezhuan": 3.0, "jianghu": 2.6}.get(self.style, 1.8)
        return ins.reverb_stereo(self.L, self.R, secs, wet)

    def line_starts(self, mel: list) -> list:
        seen = {}
        for b, semi, d, ln, end, sec in mel:
            seen.setdefault(ln, (b, sec))
        return sorted(seen.values())

    def line_beat(self, ln: int) -> float:
        return self.intro + ln * 8

    def lead_dizi(self, mel: list, gain: float, pan: float, octave: int = 0) -> None:
        for b, semi, d, *_ in mel:
            grace = 0
            if d >= 1 and self.r.random() < 0.35:
                grace = penta_step(semi, 1) - semi
            self.add(ins.dizi(self.hz(semi + 12 * octave), d * self.beat * 0.97, 1.0, grace), b, gain, pan)

    def lead_xiao(self, mel: list, gain: float, pan: float, octave: int = 0) -> None:
        prev = None
        for b, semi, d, *_ in mel:
            scoop = d >= 1 or prev is None or abs(semi - prev) > 4
            self.add(ins.xiao(self.hz(semi + 12 * octave), d * self.beat * 0.98, 1.0, scoop), b, gain, pan)
            prev = semi

    def lead_guqin(self, mel: list, gain: float, pan: float, octave: int = 0) -> None:
        for i, (b, semi, d, *_ ) in enumerate(mel):
            nxt = mel[i + 1][1] if i + 1 < len(mel) else None
            slide = 0.0
            if d >= 1.5 and nxt is not None and 0 < abs(nxt - semi) <= 5 and self.r.random() < 0.45:
                slide = nxt - semi
            self.add(ins.guqin(self.hz(semi + 12 * octave), d * self.beat, 1.0, slide, yin=d >= 2), b, gain, pan)

    def lead_bili(self, mel: list, gain: float, pan: float, octave: int = 0) -> None:
        prev = None
        for b, semi, d, *_ in mel:
            f = self.hz(semi + 12 * octave)
            frm = self.hz(prev + 12 * octave) if prev is not None and d <= 1 and abs(semi - prev) <= 5 and self.r.random() < 0.5 else 0.0
            self.add(ins.bili(f, d * self.beat * 0.96, 1.0, frm), b, gain, pan)
            prev = semi

    def hetero(self, mel: list, inst, gain: float, pan: float, octave: int = -1, fill: bool = True) -> None:
        """支声伴奏：在每拍的拍头弹那一刻的旋律音（低八度），遇到两拍以上的长音在后半加一个邻音花。"""
        for b, semi, d, *_ in mel:
            if (b - self.intro) % 1 > 1e-6 and d < 1:
                continue
            s = semi + 12 * octave
            self.add(inst(self.hz(s)), b, gain * (1.0 if (b % 2) < 1e-6 else 0.8), pan)
            if fill and d >= 2:
                self.add(inst(self.hz(penta_step(s, 1))), b + d - 1, gain * 0.55, pan)
                self.add(inst(self.hz(s)), b + d - 0.5, gain * 0.5, pan)

    def drone(self, mel: list, gain: float, every: int = 1) -> None:
        """古琴低音：每句开头弹一下调式主音（低八度），下片换成主音上方五度。"""
        for ln, (b, sec) in enumerate(self.line_starts(mel)):
            if ln % every:
                continue
            root = self.home - 12 if ln % 4 != 2 else penta_step(self.home, 3) - 24
            self.add(ins.guqin(self.hz(root), 8 * self.beat, 1.0, 0.0, yin=True), b, gain, 0.0)

    def clap_line_ends(self, mel: list, gain: float) -> None:
        """檀板：每句落在句尾长音上时「啪」一声（宋词按「拍」唱，拍板打在句读上）。"""
        for b, semi, d, ln, end, sec in mel:
            if end:
                self.add(ins.paiban(1.0, ln), b, gain, 0.25)

    # 大地图
    def arr_jianghu(self, mel: list) -> None:
        self.lead_dizi(mel, 1.0, -0.15)
        self.hetero(mel, lambda f: ins.zheng(f, 1.2), 0.9, 0.35, 0)
        self.drone(mel, 0.9)
        self.clap_line_ends(mel, 0.45)
        # 下片用洞箫低八度衬一层
        self.lead_xiao([m for m in mel if m[5] == 1], 0.45, 0.3, -1)

    # 城镇
    def arr_jieshi(self, mel: list) -> None:
        self.lead_dizi(mel, 1.0, -0.2)
        for b, semi, d, *_ in mel:
            self.add(ins.pipa(self.hz(semi - 12)), b, 0.7, 0.35)
            if d >= 1.5:
                self.add(ins.pipa(self.hz(semi - 12), d * self.beat * 0.8, 1.0, tremolo=True), b + 0.5, 0.45, 0.35)
        self.drone(mel, 0.55, 2)
        total = self.length_beats
        for bar in range(total // 4):
            b0 = bar * 4
            self.add(ins.paiban(1.0, bar), b0, 0.5, 0.2)
            self.add(ins.paiban(0.6, bar + 0.5), b0 + 2, 0.35, 0.2)
            for k, v in enumerate([0.9, 0.4, 0.6, 0.4, 0.8, 0.4, 0.6, 0.5]):
                if k in (0, 3, 5, 6):
                    self.add(ins.bangu(v, bar * 8 + k), b0 + k * 0.5, 0.9, -0.3)
            self.add(ins.muyu(0.7, 1.0), b0 + 1.5, 0.6, 0.45)
            self.add(ins.muyu(0.6, 1.12), b0 + 3.5, 0.5, 0.45)
            if bar % 2 == 0:
                self.add(ins.tanggu(0.7, bar), b0, 0.8, 0.0)
            if bar % 8 == 0:
                self.add(ins.xiaoluo(0.8), b0, 0.35, -0.1)

    # 郊野、山道
    def arr_jiaoye(self, mel: list) -> None:
        self.lead_xiao(mel, 1.0, -0.1)
        # 古琴只在每两拍的拍头应和一下，留白多
        for b, semi, d, *_ in mel:
            if (b - self.intro) % 2 < 1e-6 or d >= 3:
                self.add(ins.guqin(self.hz(semi - 12), min(d, 2) * self.beat, 1.0), b, 0.55, 0.3)
        self.drone(mel, 0.65, 2)
        for ln, (b, sec) in enumerate(self.line_starts(mel)):
            if ln % 4 == 0:
                self.add(ins.qing(self.hz(self.home + 12), 0.8), b, 0.22, -0.4)
        w = ins.wind(self.length + 8)
        self.L += w[: len(self.L)] * 0.9
        self.R += np.roll(w, SR * 3)[: len(self.R)] * 0.9

    # 列传
    def arr_liezhuan(self, mel: list) -> None:
        self.lead_guqin(mel, 1.0, -0.1)
        # 洞箫只在下片和长音上轻轻跟着
        for b, semi, d, ln, end, sec in mel:
            if sec == 1 or (d >= 2 and sec != 0):
                self.add(ins.xiao(self.hz(semi), d * self.beat * 0.98), b + 0.08, 0.5, 0.35)
        self.drone(mel, 0.55, 2)
        for b, semi, d, ln, end, sec in mel:
            if end and ln % 2 == 1:
                self.add(ins.paiban(1.0, ln), b, 0.4, 0.25)

    # 战斗：开头号角 + 擂鼓
    def battle_intro(self, bars: int) -> None:
        if not bars:
            return
        beats = bars * 4
        self.add(ins.horn(self.hz(self.home - 24), beats * 0.5 * self.beat), 0, 0.9, -0.2, False)
        self.add(ins.horn(self.hz(penta_step(self.home, 3) - 24), beats * 0.4 * self.beat), beats * 0.55, 0.8, 0.2, False)
        # 擂鼓由疏到密
        b = 0.0
        step = 1.0
        while b < beats - 0.5:
            self.add(ins.dagu(0.6 + 0.4 * b / beats, b), b, 0.9, 0.0)
            b += step
            step = max(0.25, step * 0.86)
        self.add(ins.daluo(1.0), beats - 0.0, 0.8, 0.0, False)
        self.add(ins.bo(1.0, True), beats - 0.0, 0.5, 0.3, False)

    def drums(self, pattern: dict, gain: float) -> None:
        """按每小节的鼓谱打完整首（跳过引子）；pattern = {乐器: [(拍, 力度)]}。"""
        for bar in range(self.intro // 4, self.length_beats // 4):
            b0 = bar * 4
            for name, hits in pattern.items():
                for at, v in hits:
                    if name == "dagu":
                        s, pan = ins.dagu(v, bar + at), 0.0
                    elif name == "tanggu":
                        s, pan = ins.tanggu(v, bar + at), 0.25
                    elif name == "bangu":
                        s, pan = ins.bangu(v, bar + at), -0.35
                    elif name == "bo":
                        s, pan = ins.bo(v, False, bar + at), 0.4
                    else:
                        raise ValueError(name)
                    self.add(s, b0 + at, gain, pan)

    def section_marks(self, mel: list) -> None:
        """每段开头一声大锣 + 钹。"""
        done = set()
        for b, semi, d, ln, end, sec in mel:
            if sec not in done:
                done.add(sec)
                self.add(ins.daluo(0.9), self.line_beat(ln), 0.6, -0.1)
                self.add(ins.bo(0.9, True, sec), self.line_beat(ln), 0.4, 0.35)

    def ostinato(self, degrees: list, inst, gain: float, pan: float, octave: int = -1) -> None:
        """伴奏的固定音型：每半拍一个音，两小节一换（主音 / 主音上方四度）。"""
        for bar in range(self.intro // 4, self.length_beats // 4):
            shift = 0 if (bar // 2) % 4 != 2 else 5
            for k, deg in enumerate(degrees):
                s = penta_step(self.home + 12 * octave, deg) + shift
                self.add(inst(self.hz(s)), bar * 4 + k * 0.5, gain * (1.0 if k % 2 == 0 else 0.7), pan)

    def arr_z1(self, mel: list) -> None:
        self.battle_intro(self.intro // 4)
        self.lead_bili(mel, 1.6, -0.1)
        self.ostinato([0, 0, 2, 0, 3, 0, 2, 1], lambda f: ins.pipa(f), 0.6, 0.35)
        self.hetero(mel, lambda f: ins.zheng(f, 0.6), 0.45, -0.4, -1, False)
        self.drums({
            "dagu": [(0, 1.0), (1.5, 0.8), (2, 1.0), (3, 0.7)],
            "tanggu": [(0.5, 0.5), (1, 0.6), (2.5, 0.5), (3.25, 0.4), (3.5, 0.6), (3.75, 0.5)],
            "bo": [(1, 0.6), (3, 0.6)],
        }, 0.9)
        self.section_marks(mel)

    def arr_z2(self, mel: list) -> None:
        self.battle_intro(self.intro // 4)
        for b, semi, d, ln, end, sec in mel:
            tremolo = d >= 1
            self.add(ins.pipa(self.hz(semi), d * self.beat * 0.95, 1.0, tremolo), b, 1.1 if tremolo else 1.3, -0.15)
        self.lead_dizi([m for m in mel if m[5] % 2 == 1], 0.6, 0.3)
        self.ostinato([0, 3, 2, 3, 0, 3, 2, 4], lambda f: ins.zheng(f, 0.5), 0.5, 0.4)
        self.drums({
            "dagu": [(0, 1.0), (2.5, 0.8)],
            "tanggu": [(1, 0.6), (3, 0.7), (3.5, 0.5)],
            "bangu": [(0.5, 0.4), (1.5, 0.5), (2, 0.4), (2.75, 0.4), (3.25, 0.5), (3.75, 0.6)],
            "bo": [(2, 0.5)],
        }, 0.9)
        self.section_marks(mel)

    def arr_z3(self, mel: list) -> None:
        self.battle_intro(self.intro // 4)
        self.lead_dizi(mel, 1.0, -0.1)
        self.lead_bili([m for m in mel if m[5] % 2 == 1], 1.1, 0.3, -1)
        self.ostinato([0, 2, 0, 3, 0, 2, 4, 3], lambda f: ins.pipa(f), 0.55, 0.35)
        self.drums({
            "dagu": [(0, 1.0), (1, 0.8), (2, 1.0), (3, 0.8)],
            "tanggu": [(0.5, 0.5), (1.5, 0.5), (2.5, 0.5), (3.5, 0.7), (3.75, 0.5)],
            "bo": [(1, 0.5), (3, 0.5)],
        }, 0.9)
        self.section_marks(mel)
        for ln, (b, sec) in enumerate(self.line_starts(mel)):
            if ln % 2 == 0:
                self.add(ins.xiaoluo(0.7), b, 0.3, -0.3)


SCORES_BY_STYLE = {
    "jianghu": SCORES["jianghu"], "jieshi": SCORES["jieshi"], "jiaoye": SCORES["jiaoye"], "liezhuan": SCORES["liezhuan"],
    "z1": SCORES["zhandou_1"], "z2": SCORES["zhandou_2"], "z3": SCORES["zhandou_3"],
}


def loudness(wav: Path) -> float:
    """用 ffmpeg 量响度（LUFS）。"""
    err = subprocess.run(["ffmpeg", "-nostats", "-i", str(wav), "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", err)[-1])


def write_wav(path: Path, left: np.ndarray, right: np.ndarray) -> None:
    stereo = np.clip(np.stack([left, right], axis=1), -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((stereo * 32767).astype(np.int16).tobytes())


def master(left: np.ndarray, right: np.ndarray, lufs: float, tmp: Path) -> tuple:
    """调到目标响度；峰值超过 -1 dB 的部分用软削波压住。"""
    peak = max(np.abs(left).max(), np.abs(right).max())
    left, right = left / peak * 0.5, right / peak * 0.5
    for _ in range(3):
        write_wav(tmp, left, right)
        gain = 10 ** ((lufs - loudness(tmp)) / 20)
        left, right = left * gain, right * gain
        ceiling = 0.89
        left = np.where(np.abs(left) > ceiling * 0.8, np.sign(left) * (ceiling * 0.8 + ceiling * 0.2 * np.tanh((np.abs(left) - ceiling * 0.8) / (ceiling * 0.2))), left)
        right = np.where(np.abs(right) > ceiling * 0.8, np.sign(right) * (ceiling * 0.8 + ceiling * 0.2 * np.tanh((np.abs(right) - ceiling * 0.8) / (ceiling * 0.2))), right)
    return left, right


def write_ogg(left: np.ndarray, right: np.ndarray, path: Path, lufs: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wav = path.with_suffix(".wav")
    left, right = master(left, right, lufs, wav)
    write_wav(wav, left, right)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "3", str(path)], check=True)
    wav.unlink()


def main() -> None:
    # 默认不生成战斗曲：游戏里的战斗配乐现在用的是真录音（zhandou_1~3.ogg），合成版要点名才生成，免得覆盖
    default = [n for n in TRACKS if not n.startswith("zhandou")]
    names = sys.argv[1:]
    out_dir = OUT
    if names and names[0].startswith("--out="):
        out_dir = Path(names.pop(0)[6:])
    names = names or default
    for name in names:
        cfg = TRACKS[name]
        song = Song(**cfg)
        left, right = song.render()
        out = out_dir / f"{name}.ogg"
        write_ogg(left, right, out, cfg["lufs"])
        print(f"{name}: {len(left) / SR:.0f} 秒 → {out}（{out.stat().st_size // 1024} KB）")


if __name__ == "__main__":
    main()
