class_name CameraRig
extends Camera3D
## 跟随相机：开跑前环绕展示人物，开跑后平滑切到身后视角；
## 转弯时平滑转向，绊倒 / 撞击时震屏，速度越快视野越宽。

const FOLLOW_OFFSET := Vector3(0, 4.2, 6.8)
const LOOK_AHEAD := Vector3(0, 1.1, -7.0)

@export var player: Player

var follow := false
var _blend := 0.0
var _yaw := 0.0
var _orbit := 0.0
var _focus := Vector3.ZERO
var _shake := 0.0


func _ready() -> void:
	fov = 66.0
	near = 0.1
	far = 260.0
	current = true


func reset(p_follow: bool) -> void:
	follow = p_follow
	_blend = 1.0 if follow else 0.0
	_yaw = Track.yaw_of(player.heading)
	_focus = _target_focus()
	_shake = 0.0
	_apply(0.0)
	reset_physics_interpolation()


func start_follow() -> void:
	follow = true
	_blend = 0.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _target_focus() -> Vector3:
	var p := player.leg_origin + player.fwd * player.s + player.right * player.lateral * 0.65
	var lift := maxf(player.y, 0.0) * 0.45
	return p + Vector3.UP * lift


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_apply(delta)


func _apply(delta: float) -> void:
	var k := 1.0 - exp(-20.0 * delta) if delta > 0.0 else 1.0
	_focus = _focus.lerp(_target_focus(), k)
	_yaw = lerp_angle(_yaw, Track.yaw_of(player.heading), 1.0 - exp(-7.0 * delta) if delta > 0.0 else 1.0)
	_orbit += delta

	var b := Basis(Vector3.UP, _yaw)
	var follow_pos := _focus + b * FOLLOW_OFFSET
	var follow_look := _focus + b * LOOK_AHEAD

	var menu_angle := _yaw + PI * 0.85 + sin(_orbit * 0.35) * 0.4
	var menu_pos := player.position + Basis(Vector3.UP, menu_angle) * Vector3(0, 1.5, 5.6)
	var menu_look := player.position + Vector3(0, 0.35, 0)

	if follow:
		_blend = minf(1.0, _blend + delta * 1.4)
	var t := smoothstep(0.0, 1.0, _blend)
	var pos := menu_pos.lerp(follow_pos, t)
	var look := menu_look.lerp(follow_look, t)
	global_position = pos
	if not pos.is_equal_approx(look):
		look_at(look, Vector3.UP)

	var target_fov := 66.0 + clampf(player.speed - Track.BASE_SPEED, 0.0, 20.0) * 0.35
	if player.boost_t > 0.0:
		target_fov += 8.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-3.0 * delta) if delta > 0.0 else 1.0)

	_shake = maxf(0.0, _shake - delta * 2.5)
	h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
