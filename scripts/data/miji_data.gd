class_name MijiData
extends Resource
## 一本秘籍：一条被动、追击或开局效果，装在秘籍栏里（每人一格）。
## 绝品是好汉结义时传授的独门秘籍，每位好汉一本；凡、良、精品从集市、悬赏、宝箱里来。

enum Quality { FAN, LIANG, JING, JUE }
const QUALITY_NAMES: Array[String] = ["凡品", "良品", "精品", "绝品"]
## 集市买一本的价钱（只卖凡品）
const FAN_PRICE := 120

@export var id: StringName
@export var display_name: String
@export var quality: Quality
@export_multiline var flavor: String
## 绝品：传授这本秘籍的好汉
@export var owner: StringName
## 效果，写法和天赋一样（按 1 档算）
@export var effect: TalentData

@export_group("技能书")
## 技能书：按原著故事线用好汉的将魂合成（见 Books）。story 是那段故事，recipe 是要谁的将魂
@export var story := ""
@export var recipe: Array[StringName] = []
## 统领研读这本书学会的武学（研读后书没了）
@export var martial: MartialData


func is_book() -> bool:
	return not recipe.is_empty()


func quality_name() -> String:
	return QUALITY_NAMES[quality]


## 「追击」「开局」「被动」
func category() -> String:
	return effect.category()


## 「【追击】普攻后 30% 再刺一枪，80% 伤害」
func summary() -> String:
	return "【%s】%s" % [category(), effect.describe(1)]
