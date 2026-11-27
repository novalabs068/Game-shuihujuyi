shader_type canvas_item;
render_mode blend_add;
// 卡牌背后的光：沿着卡的圆角边缘向外发光，边缘像火苗一样往上窜、明暗跳动；卡顶上再冲出一道柔和的光柱。
// 叠加混合。矩形比卡大一圈（rect_size），卡在正中（card_size），像素为单位。
// 手机上精度低、颜色 8 位：噪声用整数哈希、多层叠加（火苗细腻不分块），最后加抖动抹掉色阶。

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 1.0;
uniform vec2 rect_size = vec2(400.0, 700.0);
uniform vec2 card_size = vec2(220.0, 330.0);
// 卡在矩形里的中心（像素）
uniform vec2 card_center = vec2(200.0, 450.0);
uniform float radius = 8.0;
// 光往外散多远（像素）
uniform float spread = 26.0;
// 光柱的亮度
uniform float beam = 0.7;

float hash(ivec2 p) {
	uint h = uint(p.x) * 1597334677u ^ uint(p.y) * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = h ^ (h >> 13u);
	return float(h & 0xffffu) / 65535.0;
}

float noise(vec2 p) {
	highp vec2 fl = floor(p);
	ivec2 i = ivec2(fl);
	vec2 f = p - fl;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + ivec2(1, 0)), u.x), mix(hash(i + ivec2(0, 1)), hash(i + ivec2(1, 1)), u.x), u.y);
}

// 三层噪声叠在一起，大团里有细碎的变化
float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 7.3) * 0.3 + noise(p * 4.3 + 13.1) * 0.15;
}

void fragment() {
	float fade = COLOR.a;
	highp vec2 p = UV * rect_size - card_center;
	highp vec2 q = abs(p) - card_size * 0.5 + radius;
	highp float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	highp float t = mod(TIME, 1000.0);
	// 火苗：噪声往上流动，越往上散得越远
	float n = fbm(vec2(p.x * 0.03, p.y * 0.02 + t * 2.0));
	float up = clamp(-p.y / card_size.y, -0.5, 1.0);
	float s = spread * (0.55 + n * 1.0) * (1.0 + max(up, 0.0) * 0.8);
	// 贴边一圈亮、外面一层软，两层合起来过渡更柔
	float edge = d > 0.0 ? exp(-d / s) * 0.8 + exp(-d / (s * 2.6)) * 0.35 : 0.0;
	// 光柱：从卡顶往上，中间亮两边柔，越高越淡，里面有往上飘的细丝
	float top = -card_size.y * 0.5;
	float h = clamp((top - p.y) / (rect_size.y * 0.6), 0.0, 1.0);
	float w = card_size.x * (0.42 + h * 0.25);
	float column = exp(-(p.x * p.x) / (w * w)) * pow(1.0 - h, 1.5) * smoothstep(top + 30.0, top - 10.0, p.y);
	column *= 0.7 + 0.3 * fbm(vec2(p.x * 0.025, p.y * 0.008 + t * 1.2));
	float flicker = 0.92 + 0.08 * noise(vec2(t * 6.0, 3.7));
	// 离矩形边越近越淡，到边上正好是 0，不会切出一块方形的亮区
	highp vec2 px = UV * rect_size;
	float border = min(min(px.x, rect_size.x - px.x), min(px.y, rect_size.y - px.y));
	float frame_fade = smoothstep(0.0, 70.0, border);
	float v = (edge * 1.1 + column * beam) * intensity * flicker * fade * frame_fade;
	vec3 c = mix(color.rgb, vec3(1.0), clamp(edge * edge * 0.25, 0.0, 1.0));
	vec3 rgb = c * v;
	rgb += (hash(ivec2(FRAGCOORD.xy)) - 0.5) / 255.0 * step(0.002, v);
	COLOR = vec4(max(rgb, vec3(0.0)), 1.0);
}
