shader_type canvas_item;
// 立体翻牌：把卡当成一块有厚度的板，绕竖轴转 angle（0 = 背面朝外，PI = 正面朝外），按透视画出来。
// 挂在比卡大一圈的 ColorRect 上（rect_size，卡在正中，像素为单位）：转的时候近的一边变大、远的一边变小，
// 转到侧面时露出卡的厚度（thickness 像素）。正面来自 SubViewport 里的好汉卡，背面是锦缎卡背图。
// 翻开后 sweep 从 -0.3 走到 1.3，一道斜的高光从卡面扫过。
// 做法：对每个像素反推它落在卡面（或卡边）上的哪一点，再去取图，这样透视下图不会被三角形拉歪。

uniform sampler2D front_tex : filter_linear, repeat_disable;
uniform sampler2D back_tex : filter_linear, repeat_disable;
uniform vec2 rect_size = vec2(340.0, 450.0);
uniform vec2 card_size = vec2(220.0, 330.0);
uniform float angle = 0.0;
// 眼睛离卡多远（像素）：越小透视越夸张
uniform float depth = 900.0;
uniform float thickness = 10.0;
uniform vec4 edge_color : source_color = vec4(0.72, 0.52, 0.2, 1.0);
uniform float sweep = -1.0;
uniform vec4 sweep_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);

void fragment() {
	vec2 p = UV * rect_size - rect_size * 0.5;
	float c = cos(angle);
	float s = sin(angle);
	vec2 half_card = card_size * 0.5;
	vec4 col = vec4(0.0);
	// 卡面：卡上一点 (u, v) 转过去后 x = u·c、z = u·s，投影 X = x·d/(d+z)，反推 u
	float den = c * depth - p.x * s;
	bool hit = false;
	if (abs(den) > 0.001) {
		float u = p.x * depth / den;
		float f = depth / (depth + u * s);
		float v = p.y / f;
		if (f > 0.0 && abs(u) <= half_card.x && abs(v) <= half_card.y) {
			vec2 uv;
			if (c >= 0.0) {
				uv = vec2(0.5 + u / card_size.x, 0.5 + v / card_size.y);
				col = texture(back_tex, uv);
			} else {
				// 转过来的是正面：左右是反的
				uv = vec2(0.5 - u / card_size.x, 0.5 + v / card_size.y);
				col = texture(front_tex, uv);
				float k = uv.x + uv.y * 0.45;
				float band = exp(-pow((k - sweep * 1.45) / 0.07, 2.0));
				col.rgb += sweep_color.rgb * band * 0.75 * col.a;
			}
			// 越转到侧面越暗一点，像光照在斜面上
			col.rgb *= 0.7 + 0.3 * abs(c);
			hit = col.a > 0.01;
		}
	}
	// 卡边：u = ±半宽，厚度方向 w；X = (e·c − w·s)·d / (d + e·s + w·c)，反推 w
	if (!hit) {
		for (int i = 0; i < 2; i++) {
			float e = i == 0 ? half_card.x : -half_card.x;
			float wden = p.x * c + s * depth;
			if (abs(wden) < 0.001) continue;
			float w = (e * c * depth - p.x * depth - p.x * e * s) / wden;
			if (abs(w) > thickness * 0.5) continue;
			float z = depth + e * s + w * c;
			if (z <= 0.0) continue;
			float v = p.y * z / depth;
			if (abs(v) > half_card.y) continue;
			float lit = 0.75 + 0.35 * abs(s);
			col = vec4(edge_color.rgb * lit * (0.85 + 0.15 * (w / thickness + 0.5)), 1.0);
			break;
		}
	}
	COLOR = col * COLOR;
}
