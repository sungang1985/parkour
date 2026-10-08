class_name Player
extends Node3D
## 玩家：沿当前“路段”自动前进，三条道之间切换；
## 上滑跳、下滑翻滚、在路口左右滑转弯。碰撞用 Area3D 检测。

signal died(cause: String)
signal stumbled
signal coins_changed(coins: int)
signal powerup_started(kind: String, duration: float)
signal shield_changed(active: bool)
signal turned
signal message(text: String)

enum State { IDLE, RUNNING, DEAD }

const LANE_CHANGE_SPEED := 15.0
const JUMP_HEIGHT := 1.6
const BASE_AIR_TIME := 0.72
const BASE_ROLL_TIME := 0.75
const STUMBLE_WINDOW := 7.0
const TURN_LATE := 3.0
const BOOST_TIME := 4.0
const MAGNET_TIME := 9.0
const DOUBLE_TIME := 10.0
const STAND_SIZE := Vector3(0.7, 1.7, 0.6)
const ROLL_SIZE := Vector3(0.7, 0.8, 0.6)

@export var track: Track

var state: State = State.IDLE
var hero: Dictionary = {}

var heading := 0
var fwd := Vector3.FORWARD
var right := Vector3.RIGHT
var leg_origin := Vector3.ZERO
var s := 0.0
var path_dist := 0.0
var distance := 0.0
var lane := 1
var prev_lane := 1
var lateral := 0.0
var y := 0.0
var vy := 0.0
var gravity := 30.0
var rolling := false
var roll_t := 0.0
var roll_time := BASE_ROLL_TIME
var roll_after_land := false
var jump_buffer := 0.0
var queued_turn := 0
var speed := 0.0
var slow_t := 0.0
var stumble_t := 0.0
## 追兵贴身的剩余时间（只影响追兵远近，不影响判定）
var chase_t := 0.0
var invuln_t := 0.0
var boost_t := 0.0
var magnet_t := 0.0
var double_t := 0.0
var has_shield := false
var coins := 0
var score := 0.0
var death_cause := ""
var turns_made := 0
var revives := 0

var model: HeroModel
var _hitbox: Area3D
var _hit_shape: BoxShape3D
var _hit_cs: CollisionShape3D
var _magnet: Area3D
var _shadow: MeshInstance3D


func _ready() -> void:
	model = HeroModel.new()
	add_child(model)
	_shadow = Props.part(self, "disc", Vector3(0.9, 0.01, 0.7), Vector3(0, 0.02, 0), Color(0, 0, 0, 0.35))

	_hitbox = Area3D.new()
	_hitbox.collision_layer = 1
	_hitbox.collision_mask = Obstacle.LAYER | Pickup.LAYER
	_hitbox.monitorable = false
	_hit_cs = CollisionShape3D.new()
	_hit_shape = BoxShape3D.new()
	_hit_cs.shape = _hit_shape
	_hitbox.add_child(_hit_cs)
	add_child(_hitbox)
	_hitbox.area_entered.connect(_on_area_entered)
	_set_hitbox(STAND_SIZE)

	_magnet = Area3D.new()
	_magnet.collision_layer = 0
	_magnet.collision_mask = Pickup.LAYER
	_magnet.monitorable = false
	_magnet.monitoring = false
	var mcs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 7.0
	mcs.shape = sphere
	mcs.position = Vector3(0, 1.0, -2.0)
	_magnet.add_child(mcs)
	add_child(_magnet)
	_magnet.area_entered.connect(_on_magnet_area_entered)


func _set_hitbox(size: Vector3) -> void:
	_hit_shape.size = size
	_hit_cs.position = Vector3(0, size.y * 0.5, 0)


func setup_hero(h: Dictionary) -> void:
	hero = h
	model.build(h)


func reset() -> void:
	state = State.IDLE
	heading = 0
	fwd = Track.dir_of(0)
	right = Track.dir_of(1)
	leg_origin = Vector3.ZERO
	s = 0.0
	path_dist = 0.0
	distance = 0.0
	lane = 1
	prev_lane = 1
	lateral = 0.0
	y = 0.0
	vy = 0.0
	rolling = false
	roll_after_land = false
	jump_buffer = 0.0
	queued_turn = 0
	speed = 0.0
	slow_t = 0.0
	stumble_t = 0.0
	chase_t = 0.0
	invuln_t = 0.0
	boost_t = 0.0
	magnet_t = 0.0
	double_t = 0.0
	has_shield = false
	coins = 0
	score = 0.0
	death_cause = ""
	turns_made = 0
	revives = 0
	_set_hitbox(STAND_SIZE)
	_magnet.set_deferred("monitoring", false)
	_apply_transform()
	model.set_pose(HeroModel.Pose.IDLE)
	model.turn_yaw = 0.0
	reset_physics_interpolation()


func start_running() -> void:
	state = State.RUNNING
	model.set_pose(HeroModel.Pose.RUN)
	chase_t = 3.0  # 开局追兵紧随其后，几秒后被甩开
	if hero.get("start_shield", false):
		_set_shield(true)


func score_mult() -> int:
	return 2 if double_t > 0.0 else 1


func lane_x(l: int) -> float:
	return ChunkBuilder.lane_x(l)


## 距路口中心的有符号距离（负数表示尚未到达）。
func dist_to_junction(j: Dictionary) -> float:
	return (_ground_pos() - j["center"]).dot(fwd)


func turn_early_window() -> float:
	return maxf(10.0, speed * 0.6)


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left"):
		command("left")
	elif event.is_action_pressed("move_right"):
		command("right")
	elif event.is_action_pressed("jump"):
		command("up")
	elif event.is_action_pressed("slide"):
		command("down")


## 统一的操作入口：键盘、滑屏、自动驾驶都走这里。
func command(c: String) -> void:
	if state != State.RUNNING:
		return
	match c:
		"left", "right":
			var t := -1 if c == "left" else 1
			var j := track.next_junction()
			if not j.is_empty() and t in j["allowed"]:
				var sj := dist_to_junction(j)
				if sj >= -turn_early_window() and sj <= TURN_LATE:
					queued_turn = t
					if sj >= 0.0:
						_execute_turn(j, t)
					return
			_change_lane(t)
		"up":
			_jump()
		"down":
			_roll()


func _change_lane(t: int) -> void:
	var target := clampi(lane + t, 0, 2)
	if target == lane:
		return
	prev_lane = lane
	lane = target
	Sfx.play("lane", randf_range(0.9, 1.1), -6.0)


func _jump() -> void:
	if y > 0.01 or vy > 0.0:
		jump_buffer = 0.18  # 落地前一刻的上滑也算数
		return
	if rolling:
		_end_roll()
	var t := BASE_AIR_TIME * sqrt(Track.BASE_SPEED / maxf(speed, Track.BASE_SPEED))
	var h := JUMP_HEIGHT * float(hero.get("jump_mult", 1.0))
	vy = 4.0 * h / t
	gravity = 8.0 * h / (t * t)
	model.set_pose(HeroModel.Pose.JUMP)
	Sfx.play("jump", randf_range(0.95, 1.05))


func _roll() -> void:
	if y > 0.01 or vy > 0.0:
		# 空中下滑：快速落地并接翻滚
		vy = minf(vy, -18.0)
		roll_after_land = true
		return
	roll_time = BASE_ROLL_TIME * sqrt(Track.BASE_SPEED / maxf(speed, Track.BASE_SPEED))
	rolling = true
	roll_t = 0.0
	_set_hitbox(ROLL_SIZE)
	model.set_pose(HeroModel.Pose.ROLL)
	Sfx.play("roll")


func _end_roll() -> void:
	rolling = false
	_set_hitbox(STAND_SIZE)
	model.set_pose(HeroModel.Pose.RUN)


func _execute_turn(j: Dictionary, t: int) -> void:
	var p := _ground_pos()
	var c: Vector3 = j["center"]
	heading = posmod(heading + t, 4)
	fwd = Track.dir_of(heading)
	right = Track.dir_of(heading + 1)
	leg_origin = c
	s = (p - c).dot(fwd)
	lateral = (p - c).dot(right)
	lane = 1
	prev_lane = 1
	path_dist = j["path_center"] + s
	queued_turn = 0
	turns_made += 1
	model.turn_yaw += t * PI * 0.5
	track.on_player_turned(j, t)
	turned.emit()
	Sfx.play("turn")


# ---------------------------------------------------------------- 每帧更新

func _physics_process(delta: float) -> void:
	match state:
		State.RUNNING:
			_run(delta)
		State.DEAD:
			if death_cause == "fall":
				vy -= 30.0 * delta
				y += vy * delta
				s += speed * 0.4 * delta
				_apply_transform()
	model.animate(delta, speed)
	_shadow.visible = y > -0.2
	_shadow.position.y = 0.02 - y
	_shadow.scale = Vector3(0.9, 0.01, 0.7) * clampf(1.0 - y * 0.25, 0.4, 1.0)


func _run(delta: float) -> void:
	slow_t = maxf(0.0, slow_t - delta)
	stumble_t = maxf(0.0, stumble_t - delta)
	chase_t = maxf(0.0, chase_t - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	invuln_t = maxf(0.0, invuln_t - delta)
	_tick_powerups(delta)

	speed = Track.speed_at(path_dist)
	if boost_t > 0.0:
		speed *= 1.6
	if slow_t > 0.0:
		speed *= 0.75
	var ds := speed * delta
	s += ds
	path_dist += ds
	distance += ds
	score += ds * score_mult()

	var j := track.next_junction()
	if not j.is_empty():
		var sj := dist_to_junction(j)
		if sj >= 0.0:
			if queued_turn != 0:
				_execute_turn(j, queued_turn)
			elif boost_t > 0.0 or invuln_t > 0.0:
				_execute_turn(j, j["allowed"][0])

	lateral = move_toward(lateral, lane_x(lane), LANE_CHANGE_SPEED * delta)

	if y > 0.0 or vy > 0.0:
		vy -= gravity * delta
		y += vy * delta
		if y <= 0.0:
			y = 0.0
			vy = 0.0
			if jump_buffer > 0.0:
				jump_buffer = 0.0
				_jump()
			elif roll_after_land:
				roll_after_land = false
				_roll()
			else:
				model.set_pose(HeroModel.Pose.RUN)
	if rolling:
		roll_t += delta
		model.roll_progress = clampf(roll_t / roll_time, 0.0, 1.0)
		if roll_t >= roll_time:
			_end_roll()

	_apply_transform()
	track.update(path_dist)


func _tick_powerups(delta: float) -> void:
	if boost_t > 0.0:
		boost_t -= delta
		if boost_t <= 0.0:
			invuln_t = maxf(invuln_t, 1.0)
	if magnet_t > 0.0:
		magnet_t -= delta
		if magnet_t <= 0.0:
			_magnet.set_deferred("monitoring", false)
	double_t = maxf(0.0, double_t - delta)


func _ground_pos() -> Vector3:
	return leg_origin + fwd * s + right * lateral


func _apply_transform() -> void:
	position = _ground_pos() + Vector3.UP * y
	rotation.y = Track.yaw_of(heading)


# ---------------------------------------------------------------- 碰撞

func _on_area_entered(area: Area3D) -> void:
	if state != State.RUNNING:
		return
	if area is Pickup:
		_collect(area)
	elif area is Obstacle:
		_hit(area)


func _on_magnet_area_entered(area: Area3D) -> void:
	if area is Pickup and area.is_coin():
		area.attract(self)


func _collect(p: Pickup) -> void:
	if p.collected:
		return
	p.collect()
	if p.is_coin():
		coins += 1
		score += 10 * score_mult()
		coins_changed.emit(coins)
		Sfx.play("coin", randf_range(0.97, 1.05), -4.0)
		return
	Sfx.play("powerup")
	match p.kind:
		"boost":
			boost_t = BOOST_TIME * float(hero.get("boost_mult", 1.0))
			powerup_started.emit("boost", boost_t)
			message.emit("神行甲马！")
		"shield":
			_set_shield(true)
			message.emit("护心镜护体！")
		"magnet":
			magnet_t = MAGNET_TIME * float(hero.get("magnet_mult", 1.0))
			_magnet.set_deferred("monitoring", true)
			powerup_started.emit("magnet", magnet_t)
			message.emit("聚宝盆！")
		"double":
			double_t = DOUBLE_TIME
			powerup_started.emit("double", double_t)
			message.emit("替天行道 · 得分翻倍！")


func _set_shield(on: bool) -> void:
	has_shield = on
	shield_changed.emit(on)


func _hit(o: Obstacle) -> void:
	if o.consumed:
		return
	if boost_t > 0.0 or invuln_t > 0.0:
		if o.kind != Obstacle.Kind.GAP and o.kind != Obstacle.Kind.WALL:
			o.smash()
		return
	if o.kind == Obstacle.Kind.JARS:
		o.smash()
		if hero.get("break_jars", false):
			Sfx.play("stumble", 1.4, -6.0)
			return
		_stumble()
		return
	# 换道途中从侧面撞上：弹回原道并绊一下
	if o.lane >= 0 and o.lane == lane and absf(lateral - lane_x(lane)) > 0.35:
		lane = prev_lane
		_stumble()
		return
	if has_shield and o.kind != Obstacle.Kind.GAP and o.kind != Obstacle.Kind.WALL:
		_set_shield(false)
		o.smash()
		invuln_t = 1.0
		Sfx.play("shield")
		message.emit("护心镜碎了！")
		return
	match o.kind:
		Obstacle.Kind.GAP:
			_die("fall")
		Obstacle.Kind.WALL:
			_die("wall")
		Obstacle.Kind.HIGH:
			_die("hit_high")
		Obstacle.Kind.BLOCK:
			_die("hit_block")
		_:
			_die("hit_low")


func _stumble() -> void:
	model.stumble()
	Sfx.play("stumble")
	if stumble_t > 0.0:
		_die("caught")
		return
	stumble_t = STUMBLE_WINDOW
	chase_t = STUMBLE_WINDOW
	slow_t = 0.6
	stumbled.emit()
	message.emit("绊了一跤，官兵追上来了！")


func _die(cause: String) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	death_cause = cause
	rolling = false
	_set_hitbox(STAND_SIZE)
	match cause:
		"fall":
			model.set_pose(HeroModel.Pose.DEAD_FALL)
			vy = 0.0
			Sfx.play("fall")
		"caught":
			model.set_pose(HeroModel.Pose.CAUGHT)
			Sfx.play("crash", 0.8)
		_:
			model.set_pose(HeroModel.Pose.DEAD_HIT)
			Sfx.play("crash")
	died.emit(cause)


## 续命：回到路面、清掉前方障碍、短暂无敌。
func revive() -> void:
	revives += 1
	var j := track.next_junction()
	state = State.RUNNING
	if death_cause == "wall" and not j.is_empty():
		_execute_turn(j, j["allowed"][0])
	y = 0.0
	vy = 0.0
	rolling = false
	roll_after_land = false
	lateral = lane_x(lane)
	_set_hitbox(STAND_SIZE)
	invuln_t = 2.5
	stumble_t = 0.0
	chase_t = 0.0
	jump_buffer = 0.0
	slow_t = 0.0
	death_cause = ""
	track.clear_hazards_ahead(path_dist, 30.0)
	model.set_pose(HeroModel.Pose.RUN)
	_apply_transform()
	reset_physics_interpolation()
