shader_type canvas_item;
render_mode blend_add;
// 放射的光：中心一团白热的光核，外面一圈柔和光晕，再往外是粗细不一、慢慢流转、会呼吸的光芒。
// 叠加混合（越叠越亮），像真实的光而不是贴上去的色块。挂在 ColorRect 上（color 用白色，modulate.a 控制整体明暗）。
// 光在矩形内切圆的边上淡到 0，所以全屏用时矩形要比屏幕大（见 recruit_view.gd 的 FULL_RAYS）。
// 手机（兼容渲染器）上浮点精度低、屏幕颜色只有 8 位：噪声用整数哈希（不会碎成色块），最后加一点抖动抹掉渐变的色阶。

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
// 整体亮度
uniform float intensity = 1.0;
// 光心在矩形里的位置（0～1）
uniform vec2 center = vec2(0.5, 0.5);
// 矩形宽 / 高，保证光是圆的
uniform float aspect = 1.0;
// 光核半径（以矩形高为 1）
uniform float core = 0.08;
// 光芒的亮度和能照多远
uniform float ray_strength = 0.55;
uniform float reach = 0.9;
// 光芒流转的快慢
uniform float speed = 0.06;

// 整数哈希：0～1，任何精度下都稳定
float hash(ivec2 p) {
	uint h = uint(p.x) * 1597334677u ^ uint(p.y) * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = h ^ (h >> 13u);
	return float(h & 0xffffu) / 65535.0;
}

// 平滑的值噪声（五次插值，没有折角）
float noise(vec2 p) {
	highp vec2 fl = floor(p);
	ivec2 i = ivec2(fl);
	vec2 f = p - fl;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + ivec2(1, 0)), u.x), mix(hash(i + ivec2(0, 1)), hash(i + ivec2(1, 1)), u.x), u.y);
}

void fragment() {
	float fade = COLOR.a;
	highp vec2 p = UV - center;
	p.x *= aspect;
	highp float d = length(p);
	vec2 dir = d > 0.0001 ? p / d : vec2(1.0, 0.0);
	highp float t = mod(TIME, 1000.0);
	// 光芒：在方向上取噪声（方向是单位圆上的点，首尾自然接上），粗光束、中等光束、细光丝三层，反向流转
	float wide = noise(dir * 3.0 + vec2(t * speed * 4.0, 0.0));
	float mid = noise(dir * 9.0 + vec2(0.0, -t * speed * 7.0) + 17.0);
	float fine = noise(dir * 26.0 + vec2(t * speed * 3.0, 5.0));
	float rays = pow(wide, 2.0) * 0.55 + pow(mid, 3.0) * 0.6 + pow(fine, 4.0) * 0.5;
	// 光丝沿着半径方向轻轻闪动
	rays *= 0.85 + 0.15 * noise(vec2(d * 6.0 - t * 0.8, wide * 4.0));
	float ray_fall = pow(clamp(1.0 - d / reach, 0.0, 1.0), 1.6) * smoothstep(0.0, core * 1.2, d);
	float glow_core = exp(-d * d / (core * core));
	float halo = exp(-d / (core * 3.0)) * 0.55 + exp(-d / (core * 9.0)) * 0.15;
	// 离矩形边还有一段距离就淡到 0：光是圆的，不会被矩形切出方块（全屏用时矩形要比屏幕大得多）
	float r_max = 0.5 * min(aspect, 1.0);
	float window = smoothstep(r_max, r_max * 0.55, d);
	float v = (glow_core * 1.3 + halo + rays * ray_fall * ray_strength * 1.6) * intensity * fade * window;
	// 越靠中心越接近白色（太亮的光看起来发白）
	vec3 c = mix(color.rgb, vec3(1.0), clamp(glow_core * 0.8, 0.0, 1.0));
	vec3 rgb = c * v;
	// 抖动：每个像素加减不到一级颜色，渐变不再一圈圈分层
	rgb += (hash(ivec2(FRAGCOORD.xy)) - 0.5) / 255.0 * step(0.002, v);
	COLOR = vec4(max(rgb, vec3(0.0)), 1.0);
}
