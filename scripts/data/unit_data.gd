class_name UnitData
extends Resource
## 一个好汉或敌人的静态数据（1 级属性）。加新好汉 = 在 data/heroes/ 加一个 .tres。

## 身份：天罡、地煞（以后还有江湖人物）；PROTAGONIST 是原创主角，不在卡池里
enum Rarity { NONE, DISHA, TIANGANG, PROTAGONIST }
## 品级：强弱，决定抽卡概率和星数上限。和身份无关，见设计文档「好汉卡牌与招募」
enum Tier { JIA, YI, BING, DING }
enum Role { TANK, WARRIOR, ARCHER, STRATEGIST, MYSTIC }
## 职业的单字，战斗日志和相克说明里用（和 UiKit.ROLE_TAGS 一致）
const ROLE_TAGS: Array[String] = ["猛", "武", "射", "谋", "奇"]

@export var id: StringName
@export var display_name: String
@export var nickname: String
@export var rarity: Rarity
@export var role: Role
@export var tier: Tier = Tier.DING
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
## 战斗里的高清小人（同一个人，按 2 倍高度切的，见 tools/battle_sprites.py）；没有就用 map_sprite
@export var battle_sprite: Texture2D

@export_group("技能")
## 普攻的样子（战斗里按这个放动作和特效）：slash 刀剑、thrust 枪矛、heavy 斧棒禅杖、fist 拳脚、claw 爪牙（野兽）、arrow 弓箭、throw 暗器飞石火炮
@export var attack_style: StringName = &"slash"
@export var skill: SkillData
## 好汉的天赋（被动），点亮第 1 颗勾玉时解锁
@export var talent: TalentData
## 天赋现在的档次：0 未解锁、1 解锁、2 勾玉全亮强化。由 Stars.apply 在出战前设置
@export var talent_rank := 0

@export_group("装备")
## 身上装备（和「特效」类天赋）带来的特效（EquipData.EFFECTS 的键）。由 Stars.apply、Equipment.apply 在出战前设置
@export var gear_effects: Array[StringName] = []

@export_group("精英")
## 精英特性：&"iron" 铁甲（普攻伤害减半）、&"berserk" 狂暴（血量低于 30% 时攻击翻倍）。由遭遇战生成时设置
@export var elite_trait: StringName

@export_group("Boss")
@export var is_boss := false
## 血量第一次降到 50% 以下时给自己加的增益
@export var enrage_name := ""
@export var enrage_atk_bonus := 0.0
@export var enrage_turns := 3
