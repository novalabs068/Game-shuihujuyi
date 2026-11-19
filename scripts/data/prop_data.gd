class_name PropData
extends Resource
## 俯视场景里的一个大物件（建筑、门楼）。图的底边中点对齐 cell 这一格的底边中点。
## 挡不挡路由文字地图决定（建筑底下的格子写成 H 或 #）。

@export var texture: Texture2D
@export var cell: Vector2i
## 再微调的偏移（画面像素）
@export var offset: Vector2
