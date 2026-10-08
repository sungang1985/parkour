extends Node
## 自动化自检。用法（在项目根目录）：
##   godot --headless --fixed-fps 60 -- --selftest
## 带截图（需要显示环境，如 xvfb-run）：
##   godot --fixed-fps 60 --rendering-driver opengl3 -- --selftest --shots=/tmp/shots
## --fixed-fps 让每帧固定推进 1/60 秒，模拟时间与真实耗时无关，结果可复现。

var main: Node
var failures: Array[String] = []
var shots_dir := ""
var _biomes_seen := {}
var _max_step := 0.0
var _max_nodes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(shots_dir)
	GameState.save_path = "user://selftest_save.cfg"
	GameState.reset_progress()
	main.track.biome_changed.connect(func(id: String) -> void: _biomes_seen[id] = true)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK]   ", msg)
	else:
		print("  [FAIL] ", msg)
		failures.append(msg)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func shot(file_name: String) -> void:
	if shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join(file_name))
	print("  截图 %s（绘制调用 %d，可见物体 %d）" % [file_name,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


## 跑到死亡或超时，返回模拟的秒数；同时记录相邻两帧的最大位移（检查转弯是否瞬移）。
func run_until_dead(max_seconds: float) -> float:
	var p: Player = main.player
	var t := 0.0
	var last := p.position
	_max_step = 0.0
	while p.state == Player.State.RUNNING and t < max_seconds:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var step := Vector2(p.position.x - last.x, p.position.z - last.z).length()
		_max_step = maxf(_max_step, step - p.speed / 60.0)
		_max_nodes = maxi(_max_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		last = p.position
	return t


func _run() -> void:
	await frames(10)
	var p: Player = main.player
	await shot("01_menu.png")
	if not shots_dir.is_empty():
		# 截图模式：软件渲染很慢，只拍画面，不跑长时间测试。
		await _take_shots()
		get_tree().quit(0)
		return

	print("[selftest] 1. 不做任何操作，应该很快撞上障碍")
	main.track.biome_offset = 0.0
	main.seed_value = 7
	main.restart_run()
	var t := await run_until_dead(60.0)
	check(p.state == Player.State.DEAD, "无操作会出局（%.1f 秒，%.0f 米，死因 %s）" % [t, p.distance, p.death_cause])
	await frames(90)
	check(main.mode == main.Mode.OVER, "出局后进入结算界面")
	await shot("02_game_over.png")

	print("[selftest] 2. 续命")
	GameState.total_coins += 1000
	var before := GameState.total_coins
	main.revive()
	check(p.state == Player.State.RUNNING, "续命后继续奔跑")
	check(GameState.total_coins == before - 100, "续命扣除 100 铜钱")
	main.autopilot.enabled = true
	await frames(120)
	check(p.state == Player.State.RUNNING, "续命后 2 秒内安全")

	print("[selftest] 3. 自动驾驶长跑")
	var results: Array[Dictionary] = []
	for sd: int in [11, 22, 33]:
		main.seed_value = sd
		main.restart_run()
		main.autopilot.enabled = true
		t = await run_until_dead(150.0)
		results.append({"seed": sd, "t": t, "dist": p.distance, "turns": p.turns_made,
			"coins": p.coins, "alive": p.state == Player.State.RUNNING, "cause": p.death_cause,
			"step": _max_step})
		print("  seed=%d 用时 %.0f 秒 路程 %.0f 米 转弯 %d 次 铜钱 %d 存活 %s 死因 %s 最大跳变 %.2f 米" % [
			sd, t, p.distance, p.turns_made, p.coins, p.state == Player.State.RUNNING, p.death_cause, _max_step])
	var best: Dictionary = results[0]
	for r in results:
		if r["dist"] > best["dist"]:
			best = r
	check(best["dist"] > 2000.0, "自动驾驶至少有一局跑过 2000 米（最好 %.0f 米）" % best["dist"])
	check(results.all(func(r: Dictionary) -> bool: return r["dist"] > 400.0), "每局都跑过 400 米")
	check(best["turns"] >= 4, "经过多个路口转弯（%d 次）" % best["turns"])
	check(best["coins"] >= 30, "收集到铜钱（%d 枚）" % best["coins"])
	check(results.all(func(r: Dictionary) -> bool: return r["step"] < 0.3), "转弯与换道时位置连续，无瞬移")
	check(_biomes_seen.size() >= 3, "经过多个地域：%s" % ", ".join(_biomes_seen.keys()))
	check(_max_nodes < 6000, "场景节点数峰值 %d（路段及时回收）" % _max_nodes)

	print("[selftest] 4. 存档与解锁")
	GameState.reset_progress()
	GameState.total_coins = 650
	check(GameState.try_unlock("wusong"), "650 铜钱可以解锁武松")
	check(GameState.selected_hero == "wusong" and GameState.total_coins == 50, "解锁后自动出战并扣款")
	check(not GameState.try_unlock("luzhishen"), "铜钱不足不能解锁鲁智深")
	GameState.best_score = 4321
	GameState.save_game()
	GameState.reset_progress()
	GameState.load_game()
	check(GameState.best_score == 4321 and GameState.is_unlocked("wusong"), "存档读档一致")
	check(GameState.submit_run(5000, 800, 10), "刷新最高分")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	print("[selftest] 完成：%d 项失败" % failures.size())
	get_tree().quit(1 if failures.size() > 0 else 0)


func _take_shots() -> void:
	print("[selftest] 截图")
	var p: Player = main.player
	main.seed_value = 7
	main.restart_run()
	await run_until_dead(30.0)
	await frames(90)
	await shot("02_game_over.png")
	var i := 3
	for id in Biomes.ORDER:
		main.track.biome_offset = Biomes.first_path_of(id)
		main.seed_value = 5
		main.restart_run()
		main.autopilot.enabled = true
		await frames(60 * 5)
		await shot("%02d_run_%s.png" % [i, id])
		i += 1
	main.track.biome_offset = 0.0
	GameState.selected_hero = "luzhishen"
	main.go_menu()
	await frames(30)
	await shot("%02d_menu_luzhishen.png" % i)
	# 路口特写：跑到第一个路口前
	main.seed_value = 3
	main.restart_run()
	main.autopilot.enabled = false
	while not main.track.next_junction().is_empty() and p.dist_to_junction(main.track.next_junction()) < -14.0:
		if p.state != Player.State.RUNNING:
			break
		p.invuln_t = 1.0
		await get_tree().physics_frame
	await shot("%02d_junction.png" % (i + 1))
