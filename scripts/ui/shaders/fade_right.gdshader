// 右边和下边渐隐（战斗左下角探出来的半身像）
shader_type canvas_item;

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= 1.0 - smoothstep(0.62, 0.98, UV.x);
}
