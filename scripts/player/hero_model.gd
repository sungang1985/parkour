class_name HeroModel
extends Node3D
## 程序化人物模型 + 程序化动画（跑、跳、翻滚、绊倒、倒地）。
## 好汉与追兵共用：cfg 为 GameState.HEROES 中的一项，或 SOLDIER。

const SOLDIER := {
	"robe": Color("#9a2a1f"), "trim": Color("#4b4f57"), "pants": Color("#2b2b30"),
	"skin": Color("#e2b48c"), "hair": Color("#151212"),
	"hat": "helmet", "weapon": "torch_spear", "bulk": 1.0,
}

enum Pose { IDLE, RUN, JUMP, ROLL, DEAD_HIT, DEAD_FALL, CAUGHT }

var pose: Pose = Pose.IDLE
var phase := 0.0
var roll_progress := 0.0
var stumble_t := 0.0
var turn_yaw := 0.0

var _body: Node3D
var _hips: Node3D
var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _dead_t := 0.0


func build(cfg: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	var bulk: float = cfg.get("bulk", 1.0)
	var robe: Color = cfg["robe"]
	var trim: Color = cfg["trim"]
	var pants: Color = cfg["pants"]
	var skin: Color = cfg["skin"]
	var hair: Color = cfg["hair"]

	# 翻滚时绕身体中心转，所以 body 的原点放在 0.5 米高处。
	_body = Props.group(self, Vector3(0, 0.5, 0))
	_hips = Props.group(_body, Vector3(0, 0.45, 0))
	_torso = Props.group(_hips, Vector3.ZERO)
	var w := 0.5 * bulk
	Props.part(_torso, "box", Vector3(w, 0.62, 0.3 * bulk), Vector3(0, 0.33, 0), robe)
	Props.part(_torso, "box", Vector3(w + 0.04, 0.1, 0.34 * bulk), Vector3(0, 0.05, 0), trim)  # 腰带
	Props.part(_torso, "cone", Vector3(w + 0.22, 0.5, 0.42 * bulk), Vector3(0, -0.12, 0), robe.darkened(0.08), Vector3(PI, 0, 0))  # 下摆
	Props.part(_torso, "box", Vector3(0.12, 0.5, 0.02), Vector3(0, 0.36, -0.16 * bulk), trim)  # 衣襟
	# 头
	var head := Props.group(_torso, Vector3(0, 0.82, 0))
	Props.part(head, "sphere", Vector3(0.32, 0.36, 0.32), Vector3.ZERO, skin)
	Props.part(head, "cyl", Vector3(0.14, 0.12, 0.14), Vector3(0, -0.2, 0), skin)
	for ex: float in [-0.07, 0.07]:
		Props.part(head, "box", Vector3(0.05, 0.05, 0.02), Vector3(ex, 0.02, -0.155), Color("#16110d"))
		Props.part(head, "box", Vector3(0.09, 0.022, 0.02), Vector3(ex * 1.1, 0.08, -0.15), hair.darkened(0.3) if hair != skin else Color("#3a2a20"), Vector3(0, 0, -ex * 2.0))
	if cfg.get("beard", false):
		Props.part(head, "box", Vector3(0.22, 0.12, 0.06), Vector3(0, -0.12, -0.13), hair)
	match cfg.get("hat", ""):
		"futou":
			Props.part(head, "box", Vector3(0.34, 0.16, 0.32), Vector3(0, 0.16, 0.02), Color("#141414"))
			Props.part(head, "box", Vector3(0.5, 0.04, 0.05), Vector3(0, 0.12, 0.17), Color("#141414"))
		"hoop":
			Props.part(head, "sphere", Vector3(0.36, 0.3, 0.36), Vector3(0, 0.06, 0.04), hair)
			Props.part(head, "torus", Vector3(0.36, 0.3, 0.36), Vector3(0, 0.1, 0), Props.GOLD)
			Props.part(head, "box", Vector3(0.3, 0.4, 0.08), Vector3(0, -0.12, 0.17), hair)
		"bald":
			Props.part(_torso, "torus", Vector3(0.46, 0.5, 0.36), Vector3(0, 0.56, -0.02), Color("#3d2616"), Vector3(0.35, 0, 0))
		"bun":
			Props.part(head, "sphere", Vector3(0.34, 0.24, 0.34), Vector3(0, 0.1, 0.03), hair)
			Props.part(head, "sphere", Vector3(0.16, 0.16, 0.16), Vector3(0, 0.25, 0.05), hair)
			Props.part(head, "sphere", Vector3(0.09, 0.09, 0.09), Vector3(0.1, 0.24, 0.0), Color("#e0405a"))
		"helmet":
			Props.part(head, "cone", Vector3(0.42, 0.34, 0.42), Vector3(0, 0.22, 0), Props.IRON)
			Props.part(head, "sphere", Vector3(0.1, 0.1, 0.1), Vector3(0, 0.42, 0), Props.RED)
		_:
			Props.part(head, "sphere", Vector3(0.34, 0.24, 0.34), Vector3(0, 0.1, 0.03), hair)
	# 手臂（以肩为轴）
	_arm_l = Props.group(_torso, Vector3(-(w * 0.5 + 0.09), 0.6, 0))
	_arm_r = Props.group(_torso, Vector3(w * 0.5 + 0.09, 0.6, 0))
	for arm: Node3D in [_arm_l, _arm_r]:
		Props.part(arm, "box", Vector3(0.15, 0.32, 0.15), Vector3(0, -0.14, 0), robe)
		Props.part(arm, "box", Vector3(0.13, 0.3, 0.13), Vector3(0, -0.42, 0), skin)
	# 腿（以胯为轴）
	_leg_l = Props.group(_body, Vector3(-0.13 * bulk, 0.45, 0))
	_leg_r = Props.group(_body, Vector3(0.13 * bulk, 0.45, 0))
	for leg: Node3D in [_leg_l, _leg_r]:
		Props.part(leg, "box", Vector3(0.18, 0.62, 0.18), Vector3(0, -0.3, 0), pants)
		Props.part(leg, "box", Vector3(0.2, 0.16, 0.3), Vector3(0, -0.85, -0.05), Color("#1a1410"))
		Props.part(leg, "box", Vector3(0.19, 0.25, 0.19), Vector3(0, -0.68, 0), Color("#e8e2d0"))  # 绑腿
		if cfg.get("talismans", false):
			Props.part(leg, "box", Vector3(0.2, 0.22, 0.02), Vector3(0, -0.5, -0.11), Props.CLOTH_YELLOW, Vector3.ZERO, 0.6)
	# 兵器
	match cfg.get("weapon", "none"):
		"spear":
			var spear := Props.group(_torso, Vector3(0, 0.35, 0.2))
			spear.rotation = Vector3(0, 0, 0.75)
			Props.part(spear, "cyl", Vector3(0.05, 2.4, 0.05), Vector3.ZERO, Props.DARK_WOOD)
			Props.part(spear, "cone", Vector3(0.09, 0.32, 0.09), Vector3(0, 1.35, 0), Color("#c8ccd2"))
			Props.part(spear, "sphere", Vector3(0.14, 0.18, 0.14), Vector3(0, 1.12, 0), Props.RED)
		"blades":
			for side: float in [-1.0, 1.0]:
				Props.part(_torso, "box", Vector3(0.05, 0.75, 0.1), Vector3(side * 0.12, 0.3, 0.2), Color("#c8ccd2"), Vector3(0, 0, side * 0.35))
		"staff":
			var staff := Props.group(_torso, Vector3(0, 0.35, 0.22))
			staff.rotation = Vector3(0, 0, -0.6)
			Props.part(staff, "cyl", Vector3(0.07, 2.3, 0.07), Vector3.ZERO, Color("#8a8f96"))
			Props.part(staff, "torus", Vector3(0.4, 0.3, 0.4), Vector3(0, 1.25, 0), Color("#c8ccd2"), Vector3(PI / 2, 0, 0))
		"torch_spear":
			Props.part(_arm_r, "cyl", Vector3(0.05, 0.7, 0.05), Vector3(0, -0.6, -0.1), Props.DARK_WOOD, Vector3(PI / 2, 0, 0))
			Props.part(_arm_r, "sphere", Vector3(0.22, 0.32, 0.22), Vector3(0, -0.62, -0.5), Color("#ff8a2a"), Vector3.ZERO, 2.5)
			Props.part(_torso, "cyl", Vector3(0.05, 2.2, 0.05), Vector3(0.1, 0.4, 0.2), Props.DARK_WOOD, Vector3(0, 0, -0.5))
	set_pose(Pose.IDLE)


func set_pose(p: Pose) -> void:
	pose = p
	_dead_t = 0.0
	if p != Pose.ROLL:
		roll_progress = 0.0


func stumble() -> void:
	stumble_t = 0.45


## 每个物理帧调用。speed 为当前奔跑速度（米/秒）。
func animate(delta: float, speed: float) -> void:
	if _body == null:
		return
	turn_yaw = lerpf(turn_yaw, 0.0, 1.0 - exp(-14.0 * delta))
	rotation.y = turn_yaw
	stumble_t = maxf(0.0, stumble_t - delta)
	var lean := -0.18
	var body_rot := Vector3.ZERO
	var body_y := 0.5
	var legs := Vector2.ZERO
	var arms := Vector2.ZERO
	match pose:
		Pose.IDLE:
			phase += delta * 2.0
			body_y = 0.5 + sin(phase) * 0.01
			lean = 0.0
			arms = Vector2(0.1, -0.1)
		Pose.RUN:
			phase += delta * speed * 0.75
			var s := sin(phase)
			legs = Vector2(s, -s) * 0.9
			arms = Vector2(-s, s) * 0.8
			body_y = 0.5 + absf(cos(phase)) * 0.06
		Pose.JUMP:
			legs = Vector2(1.1, -0.4)
			arms = Vector2(2.2, 1.6)
			lean = -0.1
		Pose.ROLL:
			legs = Vector2(1.9, 1.7)
			arms = Vector2(1.4, 1.4)
			body_rot.x = -TAU * roll_progress
			body_y = 0.45
			lean = -0.6
		Pose.DEAD_HIT:
			_dead_t += delta
			var k := minf(1.0, _dead_t / 0.3)
			body_rot.x = 1.45 * k
			body_y = lerpf(0.5, 0.18, k)
			arms = Vector2(2.4, 2.0) * k
			legs = Vector2(0.4, -0.2) * k
			lean = 0.0
		Pose.DEAD_FALL:
			_dead_t += delta
			arms = Vector2(2.8 + sin(_dead_t * 20.0) * 0.4, 2.8 - sin(_dead_t * 20.0) * 0.4)
			legs = Vector2(0.6, -0.6) * sin(_dead_t * 14.0)
			lean = 0.3
		Pose.CAUGHT:
			_dead_t += delta
			var k := minf(1.0, _dead_t / 0.3)
			legs = Vector2(-1.4, 0.2) * k
			arms = Vector2(-0.6, -0.6) * k
			body_y = lerpf(0.5, 0.22, k)
			lean = 0.45 * k
	if stumble_t > 0.0:
		lean -= sin(stumble_t / 0.45 * PI) * 0.6
	_body.position.y = body_y
	_body.rotation = body_rot
	_hips.rotation.x = lean
	_leg_l.rotation.x = legs.x
	_leg_r.rotation.x = legs.y
	_arm_l.rotation.x = arms.x
	_arm_r.rotation.x = arms.y
