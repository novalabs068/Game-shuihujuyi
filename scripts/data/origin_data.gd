class_name OriginData
extends Resource
## 主角的出身：决定统领的职业（开局选定，之后不变）、第一门武学、美术和开局地点。
## 男女共用一个出身，女统领用 *_female 那组美术（没出图的先用男版）。

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var sort_order := 0
## 主角的属性、绝招和美术。开局时复制一份，名字换成玩家起的名字
@export var unit: UnitData
@export var start_location: StringName
## 出身自带的武学（开局主修）
@export var martial: MartialData
## 场景里歇脚时盘腿打坐的像素小人（脸朝右，和 unit.map_sprite 同样的像素比例）
@export var sit_sprite: Texture2D

@export_group("女统领的美术")
@export var portrait_female: Texture2D
@export var bust_female: Texture2D
@export var face_female: Texture2D
@export var map_sprite_female: Texture2D
@export var battle_sprite_female: Texture2D
@export var sit_sprite_female: Texture2D


## 把女版美术换到 unit 上（unit 是复制出来的统领数据）；哪张还没有就留着男版。
func apply_female_art(unit: UnitData) -> void:
	if portrait_female != null:
		unit.portrait = portrait_female
	if bust_female != null:
		unit.bust = bust_female
	if face_female != null:
		unit.face = face_female
	if map_sprite_female != null:
		unit.map_sprite = map_sprite_female
	if battle_sprite_female != null:
		unit.battle_sprite = battle_sprite_female
