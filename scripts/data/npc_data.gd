class_name NpcData
extends Resource
## 俯视场景里的一个人物。点他会走过去对话。

@export var id: StringName
@export var display_name: String
## 有对应好汉或敌人数据时，对话框显示其版画半身像，场景里也用他的头像
@export var unit: UnitData
## 场景里走动用的像素小人；不填就用 unit 的 map_sprite，再没有就画圆形头像
@export var sprite: Texture2D
@export var cell: Vector2i
## 对话台词，每行「说话人：台词」；说话人写「我」代表主角
@export var lines: PackedStringArray
## 对话结束后弹出的事件（比如支线的选择）；做过一次（标记 "event_<id>"）后不再弹出
@export var event: EventData
## 这个标记出现后，人物不再出现在场景里（比如支线结束后泼皮掉进了粪窖）
@export var hide_flag: String
## 说完话之后做的事：&"market" 打开集市，&"bounties" 打开这个地区的悬赏告示
@export var action: StringName
## 不是人而是物件（比如告示栏）：按瓦片的倍数放大，不呼吸、不转身
@export var still := false
