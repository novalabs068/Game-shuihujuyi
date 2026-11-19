class_name OriginData
extends Resource
## 主角的出身：决定主角的初始属性、绝招、美术和开局地点。

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var sort_order := 0
## 主角的属性、绝招和美术。开局时复制一份，名字换成玩家起的名字
@export var unit: UnitData
@export var start_location: StringName
