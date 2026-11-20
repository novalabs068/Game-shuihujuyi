class_name IdentitySeal
extends Control
## 身份的圆印：天罡朱红「罡」、地煞靛青「煞」、主角墨蓝「侠」。圆里一个字，金边。

const COLORS := {
	UnitData.Rarity.TIANGANG: Color("b8352a"),
	UnitData.Rarity.DISHA: Color("2f5a8a"),
	UnitData.Rarity.PROTAGONIST: Color("3a6a6a"),
}
const GLYPHS := {
	UnitData.Rarity.TIANGANG: "罡",
	UnitData.Rarity.DISHA: "煞",
	UnitData.Rarity.PROTAGONIST: "侠",
}

var rarity: UnitData.Rarity
var diameter := 36.0


static func make(p_rarity: UnitData.Rarity, d := 36.0) -> IdentitySeal:
	var seal := IdentitySeal.new()
	seal.rarity = p_rarity
	seal.diameter = d
	seal.custom_minimum_size = Vector2(d, d)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return seal


func _draw() -> void:
	if not COLORS.has(rarity):
		return
	var c := Vector2(diameter, diameter) / 2
	var r := diameter / 2
	draw_circle(c, r, Color("d9b25a"))
	draw_circle(c, r * 0.86, COLORS[rarity])
	draw_arc(c, r * 0.72, 0, TAU, 32, Color(1, 1, 1, 0.25), 1.0, true)
	var font := UiKit.cjk_font()
	var fs := int(diameter * 0.52)
	var w := font.get_string_size(GLYPHS[rarity], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w / 2, fs * 0.36), GLYPHS[rarity], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f6ecd2"))
