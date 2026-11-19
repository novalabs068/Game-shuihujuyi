class_name EventData
extends Resource
## 一个奇遇或支线事件：一段描述和几个选项。

@export var id: StringName
@export var title: String
@export_multiline var text: String
@export var choices: Array[EventChoice] = []
## 只在这些地点附近发生；空表示哪里都可能
@export var locations: Array[StringName] = []
## 只发生一次（发生过就设标记 "event_<id>"）
@export var once := false
