class_name Pickup
extends Area3D
## 可拾取物：铜钱或道具。铜钱可以被聚宝盆吸过来。

const LAYER := 4

## "coin" 或道具类型："boost" 神行甲马 / "shield" 护心镜 / "magnet" 聚宝盆 / "double" 替天行道旗
var kind := "coin"
var collected := false
var _target: Node3D
var _t := 0.0
var _visual: Node3D


func setup(p_kind: String) -> void:
	kind = p_kind
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5 if kind == "coin" else 0.7
	cs.shape = sphere
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	if kind == "coin":
		Props.coin(_visual)
	else:
		Props.powerup_visual(_visual, kind)
	_t = randf() * TAU


func is_coin() -> bool:
	return kind == "coin"


## 被聚宝盆吸引，飞向目标。
func attract(target: Node3D) -> void:
	if not collected and is_coin():
		_target = target


func collect() -> void:
	if collected:
		return
	collected = true
	set_deferred("monitorable", false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.1, 0.12)
	tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	_t += delta
	if is_coin():
		_visual.rotation.y = _t * 4.0
	else:
		_visual.rotation.y = sin(_t * 1.6) * 0.6
		_visual.position.y = sin(_t * 3.0) * 0.15
	if _target and not collected and is_instance_valid(_target):
		var goal := _target.global_position + Vector3(0, 0.9, 0)
		global_position = global_position.move_toward(goal, delta * 38.0)
