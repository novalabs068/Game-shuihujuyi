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


func grade_name() -> String:
	return GRADE_NAMES[grade]
