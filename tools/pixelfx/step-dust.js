// 水浒聚义：走路时脚后跟踢起的一小撮土。朝右走，土往左后方（-x）扬起；游戏里朝左走时水平翻转。
import { Rng, fit, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Step dust",
  desc: "A small kick of dust from the heel on each step: three or four soft puffs thrown back low along the ground, swelling, lifting a little and thinning away.",
  tags: ["dust", "step", "walk", "footstep", "one-shot"],
  size: [32, 16],
  origin: [22, 13],
  duration: 0.5,
  loop: false,
  fps: 24,
  bg: "ground",
  options: {
    palette: ["#4a3a28", "#7a6244", "#a88c64", "#ccb48a", "#e8dcbc"],
    seed: 7,
  },
};

export function create(o) {
  const C = fit(o.palette, 5), R = new Rng(o.seed);
  const puffs = [];
  for (let i = 0; i < 4; i++) {
    puffs.push({
      x: R.range(-2, 1), y: -1,
      vx: -R.range(30, 70) * (0.6 + i * 0.25), vy: -R.range(6, 22),
      r0: R.range(0.6, 1.1), r1: R.range(1.6, 2.8),
      delay: i * 0.03, life: R.range(0.3, 0.42),
    });
  }
  let t = 0;
  return {
    update(dt) {
      t += dt;
      for (const b of puffs) {
        if (t < b.delay) continue;
        b.vx -= b.vx * 6 * dt;
        b.vy -= b.vy * 5 * dt;
        b.x += b.vx * dt;
        b.y = Math.min(b.y + b.vy * dt, -0.5);
      }
    },
    draw(p) {
      for (const b of puffs) {
        const age = t - b.delay;
        if (age < 0 || age >= b.life) continue;
        const u = age / b.life;
        const r = b.r0 + (b.r1 - b.r0) * ease.outCubic(clamp(u * 1.6));
        const a = (1 - ease.inQuad(u)) * 0.95;
        // 下半边暗一级，上半边亮一级：从上方打光
        p.disc(b.x + 0.4, b.y + 0.5, r, C[1], a * 0.8);
        p.disc(b.x, b.y, r * 0.85, C[2], a);
        if (u < 0.6) p.disc(b.x - r * 0.25, b.y - r * 0.3, r * 0.4, C[3], a);
      }
    },
  };
}
