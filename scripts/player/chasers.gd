class_name Chasers
extends Node3D
## 高俅派来的追兵。平时远远落在镜头之后；玩家绊倒后会紧追到身后，
## 在“绊倒窗口”内再绊一次就会被擒。

const COUNT := 3
const FAR_GAP := 16.0
const NEAR_GAP := 2.6
const OFFSETS := [Vector3(-1.4, 0, 0.0), Vector3(1.3, 0, 0.8), Vector3(0.0, 0, 2.2)]

@export var player: Player

var _holders: Array[Node3D] = []
var _men: Array[HeroModel] = []
var _gap := FAR_GAP


func _ready() -> void:
	for i in COUNT:
		var holder := Node3D.new()
		add_child(holder)
		var m := HeroModel.new()
		holder.add_child(m)
		m.build(HeroModel.SOLDIER)
		_holders.append(holder)
		_men.append(m)


func reset() -> void:
	_gap = FAR_GAP
	visible = false
	for m in _men:
		m.set_pose(HeroModel.Pose.IDLE)
	_place(1.0)
	for h in _holders:
		h.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var running := player.state == Player.State.RUNNING
	var caught := player.state == Player.State.DEAD and player.death_cause == "caught"
	var closeness := clampf(player.chase_t / 3.0, 0.0, 1.0)
	var target_gap := lerpf(FAR_GAP, NEAR_GAP, closeness)
	if caught:
		target_gap = 1.2
	elif not running:
		target_gap = _gap
	_gap = lerpf(_gap, target_gap, 1.0 - exp(-3.0 * delta))
	visible = _gap < FAR_GAP - 1.0 or caught
	_place(1.0 - exp(-10.0 * delta))
	var moving := running or (caught and _gap > 1.35)
	var want := HeroModel.Pose.RUN if moving else HeroModel.Pose.IDLE
	for m in _men:
		if m.pose != want:
			m.set_pose(want)
		m.animate(delta, player.speed if running else 7.0)


func _place(weight: float) -> void:
	var yaw := Track.yaw_of(player.heading)
	var rot := Basis(Vector3.UP, yaw)
	var base := player.position
	base.y = 0.0
	for i in _holders.size():
		var h := _holders[i]
		var target: Vector3 = base + rot * (Vector3(0, 0, _gap) + OFFSETS[i])
		h.position = h.position.lerp(target, weight)
		h.rotation.y = lerp_angle(h.rotation.y, yaw, weight)
