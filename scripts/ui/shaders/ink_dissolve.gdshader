shader_type canvas_item;
// 倒下：人像像墨在宣纸上晕开一样化掉。progress 从 0 到 1；边缘先变成墨色再透明。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge = 0.12;
uniform vec4 ink_color : source_color = vec4(0.06, 0.045, 0.035, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// 从上往下、带着墨团的形状化开
	float n = noise(UV * 9.0) * 0.6 + noise(UV * 23.0) * 0.4;
	float v = n * 0.75 + (1.0 - UV.y) * 0.25;
	float cut = progress * (1.0 + edge);
	if (v < cut - edge) {
		c.a = 0.0;
	} else if (v < cut) {
		c.rgb = mix(c.rgb, ink_color.rgb, 0.85);
	}
	COLOR = c;
}
