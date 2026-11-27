class_name BountyData
extends Resource
## 一张悬赏告示：打一次就揭下，标记 "bounty_<id>"。

enum Grade { BING, YI, JIA }

const GRADE_NAMES: Array[String] = ["丙", "乙", "甲"]
## 各等级悬赏给的聚义令，见设计文档「地区与数值」
const GRADE_TOKENS: Array[int] = [1, 3, 6]

@export var id: StringName
@export var location: StringName
@export var grade: Grade
@export var target: String
@export_multiline var description: String
@export var stage: StageData


func tokens() -> int:
	return GRADE_TOKENS[grade]


## 悬赏给的装备品质：丙、乙等给良品，甲等给精品。
func equip_quality() -> EquipData.Quality:
	return EquipData.Quality.JING if grade == Grade.JIA else EquipData.Quality.LIANG


## 悬赏给的秘籍品质：乙等良品、甲等精品，丙等不给（-1）。
func miji_quality() -> int:
	return [-1, MijiData.Quality.LIANG, MijiData.Quality.JING][grade]


## 「、残页 3 张」或空，悬赏告示上用（秘籍改成用好汉将魂合成，悬赏给残页顶缺的将魂）。
func miji_text() -> String:
	return "、残页 %d 张" % Books.BOUNTY_PAGES[grade] if Books.BOUNTY_PAGES[grade] > 0 else ""


## 悬赏还送一份药：甲等续命膏，乙丙等金疮药。
func medicine() -> StringName:
	return &"xu_ming_gao" if grade == Grade.JIA else &"jin_chuang_yao"


## 接下悬赏开打时交给 main 的额外奖励。
func battle_bonus() -> Dictionary:
	var bonus := {"tokens": tokens(), "equip_quality": equip_quality(), "medicine": medicine(), "flag": "bounty_" + String(id), "text": "揭下了「%s」的悬赏。" % target}
	if Books.BOUNTY_PAGES[grade] > 0:
		bonus["pages"] = Books.BOUNTY_PAGES[grade]
	return bonus


func grade_name() -> String:
	return GRADE_NAMES[grade]
