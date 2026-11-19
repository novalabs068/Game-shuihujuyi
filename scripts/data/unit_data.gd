class_name UnitData
extends Resource
## 一个好汉或敌人的静态数据（1 级属性）。加新好汉 = 在 data/heroes/ 加一个 .tres。

## PROTAGONIST 是原创主角，不在卡池里
enum Rarity { NONE, DISHA, TIANGANG, PROTAGONIST }
enum Role { TANK, WARRIOR, ARCHER, STRATEGIST, MYSTIC }

@export var id: StringName
@export var display_name: String
@export var nickname: String
@export var rarity: Rarity
@export var role: Role
@export var sort_order := 0

@export_group("1 级属性")
@export var base_hp := 100
@export var base_atk := 10
@export var base_def := 10
@export var base_spd := 100

@export_group("立绘")
## 由 tools/art_pipeline.py 生成：整身立绘、卡片半身像、出手顺序头像。原图都是脸朝右。
@export var portrait: Texture2D
@export var bust: Texture2D
@export var face: Texture2D
## 俯视场景里的像素小人（全身、脸朝右），由 tools/pixel_pipeline.py 生成
@export var map_sprite: Texture2D

@export_group("技能")
@export var skill: SkillData

@export_group("Boss")
@export var is_boss := false
## 血量第一次降到 50% 以下时给自己加的增益
@export var enrage_name := ""
@export var enrage_atk_bonus := 0.0
@export var enrage_turns := 3
