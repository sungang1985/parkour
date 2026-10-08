class_name SwipeInput
extends Node
## 触屏滑动识别：手指移动超过阈值立即触发（不必等抬手），每次触摸只触发一次。
## 开启了“鼠标模拟触摸”，桌面上用鼠标拖动也能测试。

signal swiped(direction: String)

## 触发阈值占屏幕短边的比例。
@export var threshold_ratio := 0.05

var _active := false
var _index := -1
var _start := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and not _active:
			_active = true
			_index = touch.index
			_start = touch.position
		elif not touch.pressed and touch.index == _index:
			_active = false
	elif event is InputEventScreenDrag and _active:
		var drag := event as InputEventScreenDrag
		if drag.index != _index:
			return
		var d := drag.position - _start
		var vp := get_viewport().get_visible_rect().size
		if d.length() < minf(vp.x, vp.y) * threshold_ratio:
			return
		_active = false
		if absf(d.x) > absf(d.y):
			swiped.emit("right" if d.x > 0.0 else "left")
		else:
			swiped.emit("down" if d.y > 0.0 else "up")
