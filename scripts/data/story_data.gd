class_name StoryData
extends Resource
## 好汉列传的一段。招到这位好汉、打完前一段后，在 location 解锁。
## 剧情写在 script_path 指向的文本文件里，格式见 StoryScript。

@export var id: StringName
@export var hero: StringName
## 第几段（从 1 开始），前一段打完才解锁这一段
@export var order := 1
@export var title: String
@export var location: StringName
@export var recommended_level := 1
@export_file("*.txt") var script_path: String

@export_group("奖励")
@export var tokens := 0
@export var silver := 0
## 这位好汉的将魂
@export var souls := 0
## 打完这一段，好汉传授给主角的武学
@export var martial: MartialData


func flag() -> String:
	return "story_" + String(id)
