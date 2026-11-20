class_name FxSprite
extends Sprite2D
## 播一段 pixelfx 导出的像素特效（art/fx/<名字>.png，参数见 FxSheets）。
## position 对准特效的锚点（脚底、命中点）；放完一遍自动删掉，循环的一直播到 stop()。

var _fps := 30.0
var _count := 1
var _loop := false
var _time := 0.0


## 在 parent 里 at 处播 name；scale_k 是放大倍数，flip 时左右翻转（朝左的出手）。
static func spawn(parent: Node, name: String, at: Vector2, scale_k: float, flip := false, loop_override := -1) -> FxSprite:
	var spec: Array = FxSheets.SHEETS[name]
	var fx := FxSprite.new()
	fx.texture = load("res://art/fx/%s.png" % name)
	fx.hframes = spec[2]
	fx.vframes = ceili(float(spec[3]) / spec[2])
	fx._count = spec[3]
	fx._fps = spec[4]
	fx._loop = spec[5] if loop_override < 0 else loop_override == 1
	fx.centered = false
	fx.offset = -Vector2(spec[6], spec[7])
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.scale = Vector2(-scale_k if flip else scale_k, scale_k)
	fx.position = at
	fx.z_index = 15
	parent.add_child(fx)
	return fx


func _process(delta: float) -> void:
	_time += delta
	var f := int(_time * _fps)
	if f >= _count:
		if not _loop:
			queue_free()
			return
		f %= _count
	frame = f


func stop() -> void:
	queue_free()
