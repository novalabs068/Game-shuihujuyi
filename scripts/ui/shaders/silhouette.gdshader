shader_type canvas_item;
// 金边剪影：reveal = 0 时立绘是一团暗影，只有轮廓镶一道金边、往里透一点金光；reveal 走到 1 慢慢上色成原画。
// 轮廓靠透明度找：自己不透明、旁边一圈有透明的像素就是边（立绘是透明底的 PNG）。

uniform float reveal = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
// 金边多宽（贴图像素）
uniform float rim_width = 5.0;
uniform vec4 shadow_color : source_color = vec4(0.09, 0.05, 0.02, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;
	// 八个方向、两圈取样，找最小的透明度
	float near = 1.0;
	for (int r = 1; r <= 2; r++) {
		vec2 o = TEXTURE_PIXEL_SIZE * rim_width * float(r) * 0.5;
		near = min(near, texture(TEXTURE, UV + vec2(o.x, 0.0)).a);
		near = min(near, texture(TEXTURE, UV - vec2(o.x, 0.0)).a);
		near = min(near, texture(TEXTURE, UV + vec2(0.0, o.y)).a);
		near = min(near, texture(TEXTURE, UV - vec2(0.0, o.y)).a);
		near = min(near, texture(TEXTURE, UV + o).a);
		near = min(near, texture(TEXTURE, UV - o).a);
		near = min(near, texture(TEXTURE, UV + vec2(o.x, -o.y)).a);
		near = min(near, texture(TEXTURE, UV + vec2(-o.x, o.y)).a);
	}
	float rim = clamp(a - near, 0.0, 1.0);
	// 剪影：暗影底 + 从下往上淡淡的金光 + 金边
	vec3 shadow = mix(shadow_color.rgb, rim_color.rgb * 0.35, (1.0 - UV.y) * 0.25);
	vec3 sil = mix(shadow, rim_color.rgb * 2.0, rim);
	float r = smoothstep(0.0, 1.0, reveal);
	vec3 rgb = mix(sil, tex.rgb, r);
	// 上色的过程中金边还亮一会儿
	rgb += rim_color.rgb * rim * (1.0 - r) * 0.4;
	COLOR = vec4(rgb, a) * COLOR;
}
