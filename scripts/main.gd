extends Node3D
## 游戏主流程：主菜单 → 开跑 → 暂停 / 结算 → 续命或重开。
## 命令行（写在 -- 之后）调试参数：
##   --selftest         运行自动化自检后退出
##   --shots=<目录>     自检时顺带截图（需要真实渲染，不能用 --headless）
##   --biome=<地域id>   从指定地域开跑：snow / forest / huangni / jingyang / liangshan
##   --seed=<整数>      固定赛道随机种子
##   --autopilot        开跑后自动驾驶（演示）

enum Mode { MENU, RUN, PAUSED, OVER }

var mode: Mode = Mode.MENU
var seed_value := -1
var biome_offset := 0.0
var autopilot_on := false

@onready var track: Track = $Track
@onready var player: Player = $Player
@onready var chasers: Chasers = $Chasers
@onready var cam: CameraRig = $CameraRig
@onready var ui: GameUI = $UI
@onready var swipe: SwipeInput = $SwipeInput
@onready var autopilot: Autopilot = $Autopilot
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var _env: Environment
var _sky: ProceduralSkyMaterial
var _weather: CPUParticles3D
var _env_tween: Tween
var _over_delay := -1.0
var _banked_coins := 0
var _biome_instant := true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--biome="):
			biome_offset = Biomes.first_path_of(a.get_slice("=", 1))
		elif a == "--autopilot":
			autopilot_on = true

	player.track = track
	chasers.player = player
	cam.player = player
	autopilot.player = player
	autopilot.track = track
	track.biome_offset = biome_offset
	_setup_environment()

	track.biome_changed.connect(_on_biome_changed)
	player.died.connect(_on_player_died)
	player.stumbled.connect(_on_player_stumbled)
	player.message.connect(ui.toast)
	player.powerup_started.connect(ui.on_powerup)
	player.shield_changed.connect(func(on: bool) -> void:
		if not on:
			cam.shake(0.6))
	swipe.swiped.connect(player.command)
	ui.player = player
	ui.start_pressed.connect(start_run)
	ui.pause_pressed.connect(_pause)
	ui.resume_pressed.connect(_resume)
	ui.restart_pressed.connect(restart_run)
	ui.home_pressed.connect(go_menu)
	ui.revive_pressed.connect(revive)
	ui.hero_previewed.connect(func(id: String) -> void: player.setup_hero(GameState.hero_data(id)))

	go_menu()

	if "--selftest" in args:
		var test: Node = load("res://tests/self_test.gd").new()
		test.main = self
		add_child(test)


# ---------------------------------------------------------------- 流程

func _reset_world(follow: bool) -> void:
	get_tree().paused = false
	_over_delay = -1.0
	_banked_coins = 0
	_biome_instant = true
	track.reset(seed_value)
	player.setup_hero(GameState.current_hero())
	player.reset()
	chasers.reset()
	cam.reset(follow)
	autopilot.enabled = false


func go_menu() -> void:
	_finish_pending_run()
	mode = Mode.MENU
	_reset_world(false)
	ui.show_menu()


func start_run() -> void:
	if mode != Mode.MENU:
		_reset_world(true)
	mode = Mode.RUN
	# 菜单里可能正在预览未解锁的好汉，开跑时换回已出战的那位
	player.setup_hero(GameState.current_hero())
	player.start_running()
	cam.start_follow()
	autopilot.enabled = autopilot_on
	ui.show_hud()
	ui.show_hint()
	var b := Biomes.get_data(track.current_biome)
	ui.show_banner(b["name"], b["chapter"])
	Sfx.play("gong")
	Sfx.play("drum", 1.0, -3.0)


func restart_run() -> void:
	_finish_pending_run()
	_reset_world(true)
	mode = Mode.MENU
	start_run()


func revive() -> void:
	var cost := revive_cost()
	if mode != Mode.OVER or cost <= 0 or not GameState.spend_coins(cost):
		return
	player.revive()
	mode = Mode.RUN
	ui.show_hud()
	ui.toast("好汉重整旗鼓！")


func revive_cost() -> int:
	if player.revives >= 3:
		return 0
	return 100 * int(pow(2, player.revives))


func _pause() -> void:
	if mode != Mode.RUN:
		return
	mode = Mode.PAUSED
	get_tree().paused = true
	ui.show_pause(true)


func _resume() -> void:
	if mode != Mode.PAUSED:
		return
	mode = Mode.RUN
	get_tree().paused = false
	ui.show_pause(false)


## 离开本局前确保已入账：中途从暂停菜单退出，或死亡动画还没播完就离开。
## 结算界面已经弹出时（死亡时已结算）不重复入账。
func _finish_pending_run() -> void:
	if mode == Mode.RUN or mode == Mode.PAUSED or _over_delay >= 0.0:
		_settle_run()
	_over_delay = -1.0


func _settle_run() -> bool:
	var new_coins := player.coins - _banked_coins
	_banked_coins = player.coins
	return GameState.submit_run(int(player.score), int(player.distance), new_coins, player.revives == 0)


func _process(delta: float) -> void:
	if _over_delay >= 0.0:
		_over_delay -= delta
		if _over_delay < 0.0:
			var prev_best := GameState.best_score
			_settle_run()
			var cost := revive_cost()
			ui.show_game_over(player.death_cause, int(player.score), int(player.distance), player.coins,
				int(player.score) > prev_best, cost, cost > 0 and GameState.total_coins >= cost)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			match mode:
				Mode.RUN:
					_pause()
				Mode.PAUSED:
					_resume()
				Mode.OVER:
					go_menu()
				Mode.MENU:
					get_tree().quit()


# ---------------------------------------------------------------- 事件

func _on_player_died(_cause: String) -> void:
	mode = Mode.OVER
	autopilot.enabled = false
	cam.shake(1.0)
	ui.flash()
	_over_delay = 1.3


func _on_player_stumbled() -> void:
	cam.shake(0.7)
	ui.flash()


func _on_biome_changed(id: String) -> void:
	var b := Biomes.get_data(id)
	_apply_biome(b, _biome_instant)
	if not _biome_instant and mode == Mode.RUN:
		ui.show_banner(b["name"], b["chapter"])
		Sfx.play("drum")
	_biome_instant = false


# ---------------------------------------------------------------- 环境

func _setup_environment() -> void:
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_density = 1.0
	_env.fog_depth_curve = 1.4
	_env.fog_sky_affect = 0.75
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = _env
	sun.rotation_degrees = Vector3(-52.0, 32.0, 0.0)
	sun.shadow_enabled = false

	_weather = CPUParticles3D.new()
	_weather.position = Vector3(0, 8.0, -14.0)
	_weather.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_weather.emission_box_extents = Vector3(20.0, 1.0, 26.0)
	_weather.direction = Vector3(0.15, -1.0, 0.0)
	_weather.spread = 12.0
	_weather.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = m
	_weather.mesh = quad
	cam.add_child(_weather)


func _apply_biome(b: Dictionary, instant: bool) -> void:
	var targets := [
		[_sky, "sky_top_color", b["sky_top"]],
		[_sky, "sky_horizon_color", b["sky_horizon"]],
		[_sky, "ground_horizon_color", b["sky_horizon"]],
		[_sky, "ground_bottom_color", b["fog"].darkened(0.3)],
		[_env, "fog_light_color", b["fog"]],
		[_env, "fog_depth_begin", b["fog_begin"]],
		[_env, "fog_depth_end", b["fog_end"]],
		[_env, "ambient_light_color", b["ambient"]],
		[_env, "ambient_light_energy", b["ambient_energy"]],
		[sun, "light_color", b["sun"]],
		[sun, "light_energy", b["sun_energy"]],
	]
	if _env_tween:
		_env_tween.kill()
	if instant:
		for t: Array in targets:
			t[0].set(t[1], t[2])
	else:
		_env_tween = create_tween().set_parallel(true)
		for t: Array in targets:
			_env_tween.tween_property(t[0], t[1], t[2], 2.5)
	_set_weather(b["particles"])


func _set_weather(kind: String) -> void:
	match kind:
		"snow":
			_weather.amount = 360
			_weather.lifetime = 3.2
			_weather.gravity = Vector3(0, -2.0, 0)
			_weather.initial_velocity_min = 2.0
			_weather.initial_velocity_max = 3.5
			_weather.scale_amount_min = 0.7
			_weather.scale_amount_max = 1.4
			_weather.color = Color(1, 1, 1, 0.9)
			_weather.emitting = true
		"leaves":
			_weather.amount = 50
			_weather.lifetime = 4.0
			_weather.gravity = Vector3(0.6, -1.2, 0)
			_weather.initial_velocity_min = 0.5
			_weather.initial_velocity_max = 1.5
			_weather.scale_amount_min = 1.5
			_weather.scale_amount_max = 2.5
			_weather.color = Color("#d0682e")
			_weather.emitting = true
		_:
			_weather.emitting = false
