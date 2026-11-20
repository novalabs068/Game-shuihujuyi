// 把图裁成圆形（出手顺序的头像）
shader_type canvas_item;

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= 1.0 - smoothstep(0.47, 0.5, distance(UV, vec2(0.5)));
}
