class_name GameUI
extends CanvasLayer
## 全部界面：主菜单（选好汉）、局内 HUD、暂停、结算。用代码搭建，统一“宣纸 + 朱红 + 金边”风格。

signal start_pressed
signal pause_pressed
signal resume_pressed
signal restart_pressed
signal home_pressed
signal revive_pressed
signal hero_previewed(hero_id: String)

const C_GOLD := Color("#f2c94c")
const C_PAPER := Color("#f3e5c6")
const C_INK := Color("#2b1a10")
const C_RED := Color("#8e1b1b")
const C_DIM := Color(0.05, 0.03, 0.02, 0.62)

const DEATH_TEXT := {
	"hit_low": "被拒马绊翻在地",
	"hit_high": "一头撞上了横幅",
	"hit_block": "迎面撞上了拦路之物",
	"fall": "一脚踏空，坠了下去",
	"wall": "慌不择路，跑进了死胡同",
	"caught": "被官兵团团围住，擒了去",
}
const FLAVOR := [
	"大碗喝酒，大块吃肉——歇口气再跑！",
	"路见不平一声吼，该出手时就出手！",
	"好汉不吃眼前亏，重整旗鼓再来！",
	"聚义厅前，兄弟们还在等你。",
	"八百里水泊梁山，就在前方。",
]
const POWER_NAMES := {"boost": "神行甲马", "magnet": "聚宝盆", "double": "得分翻倍"}

var player: Player

var _menu: Control
var _hud: Control
var _pause: Control
var _over: Control

var _best_label: Label
var _hero_name: Label
var _hero_title: Label
var _hero_desc: Label
var _hero_perk: Label
var _hero_btn: Button
var _music_btn: Button
var _sfx_btn: Button
var _hero_idx := 0

var _score_label: Label
var _dist_label: Label
var _coin_label: Label
var _menu_coin_label: Label
var _toast: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _hint: Label
var _flash: ColorRect
var _power_box: VBoxContainer
var _bars := {}
var _shield_row: Control

var _over_title: Label
var _over_flavor: Label
var _over_stats: Label
var _over_record: Label
var _revive_btn: Button
var _toast_tween: Tween
var _banner_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_menu = _full(root)
	_hud = _full(root)
	_pause = _full(root)
	_over = _full(root)
	_build_menu()
	_build_hud()
	_build_pause()
	_build_over()
	GameState.coins_changed.connect(func(_c: int) -> void: _refresh_menu())
	show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _hud.visible and not _pause.visible:
			pause_pressed.emit()
			get_viewport().set_input_as_handled()
		elif _pause.visible:
			resume_pressed.emit()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _hud.visible or player == null:
		return
	_score_label.text = str(int(player.score))
	_dist_label.text = "%d 米" % int(player.distance)
	_coin_label.text = str(player.coins)
	for kind: String in _bars:
		var bar: ProgressBar = _bars[kind]
		var left := 0.0
		match kind:
			"boost":
				left = player.boost_t
			"magnet":
				left = player.magnet_t
			"double":
				left = player.double_t
		bar.value = left
		bar.get_parent().visible = left > 0.0
	_shield_row.visible = player.has_shield


# ---------------------------------------------------------------- 对外接口

func show_menu() -> void:
	_set_screen(_menu)
	_hero_idx = GameState.hero_index(GameState.selected_hero)
	_refresh_menu()


func show_hud() -> void:
	_set_screen(_hud)
	_flash.color.a = 0.0


func show_pause(on: bool) -> void:
	_pause.visible = on


func show_game_over(cause: String, score: int, distance: int, coins: int, record: bool,
		revive_cost: int, can_revive: bool) -> void:
	_set_screen(_over)
	_hud.visible = true
	_over_title.text = DEATH_TEXT.get(cause, "倒下了")
	_over_flavor.text = FLAVOR[randi() % FLAVOR.size()]
	_over_stats.text = "得分　%d\n路程　%d 米\n铜钱　%d\n最高　%d" % [score, distance, coins, GameState.best_score]
	_over_record.visible = record
	_revive_btn.visible = revive_cost > 0
	_revive_btn.disabled = not can_revive
	_revive_btn.text = "续命再跑（%d 铜钱）" % revive_cost


func show_hint() -> void:
	_hint.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 1.0)


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.scale = Vector2.ONE * 1.25
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.15)
	_toast_tween.tween_interval(1.1)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func flash(color := Color(0.8, 0.05, 0.02, 0.35)) -> void:
	_flash.color = color
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)


func show_banner(title: String, sub: String) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner.modulate.a = 0.0
	_banner.visible = true
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	_banner_tween.tween_interval(2.6)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


func on_powerup(kind: String, duration: float) -> void:
	if _bars.has(kind):
		_bars[kind].max_value = duration


# ---------------------------------------------------------------- 搭建

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = GameState.font_body
	t.default_font_size = 30
	t.set_color("font_color", "Label", C_PAPER)
	t.set_color("font_color", "Button", Color("#fff3d6"))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", C_GOLD)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.45))
	t.set_stylebox("normal", "Button", _box(C_RED, C_GOLD, 16, 3))
	t.set_stylebox("hover", "Button", _box(C_RED.lightened(0.12), C_GOLD, 16, 3))
	t.set_stylebox("pressed", "Button", _box(C_RED.darkened(0.25), C_GOLD, 16, 3))
	t.set_stylebox("disabled", "Button", _box(Color("#5a4a40"), Color("#8a7a60"), 16, 3))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", _box(Color(C_PAPER, 0.96), Color("#6b4a2b"), 20, 4))
	var bg := _box(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 6, 0)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	var fill := _box(C_GOLD, Color(0, 0, 0, 0), 6, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	return t


func _box(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _full(parent: Control) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _set_screen(screen: Control) -> void:
	for s: Control in [_menu, _hud, _pause, _over]:
		s.visible = s == screen


func _label(parent: Control, text: String, size: int, color := C_PAPER, title_font := false,
		outline := 0, outline_color := Color(0, 0, 0, 0.7)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title_font:
		l.add_theme_font_override("font", GameState.font_title)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, size: int, cb: Callable, title_font := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if title_font:
		b.add_theme_font_override("font", GameState.font_title)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		cb.call())
	parent.add_child(b)
	return b


func _place(c: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


func _gradient_overlay(parent: Control, top: bool, height: float, alpha: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, alpha))
	g.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0 if top else 1.0)
	tex.fill_to = Vector2(0.5, 1.0 if top else 0.0)
	tex.width = 8
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top:
		_place(r, Control.PRESET_TOP_WIDE, 0, 0, 0, height)
	else:
		_place(r, Control.PRESET_BOTTOM_WIDE, 0, -height, 0, 0)
	parent.add_child(r)


func _build_menu() -> void:
	_gradient_overlay(_menu, true, 420, 0.7)
	_gradient_overlay(_menu, false, 640, 0.75)
	var title := _label(_menu, "逼上梁山", 136, C_GOLD, true, 18, Color("#5a0e0b"))
	_place(title, Control.PRESET_TOP_WIDE, 0, 50, 0, 230)
	var sub := _label(_menu, "水浒好汉 · 风雪亡命 · 直奔梁山", 32, C_PAPER, false, 6)
	_place(sub, Control.PRESET_TOP_WIDE, 0, 222, 0, 270)
	_best_label = _label(_menu, "", 28, C_PAPER, false, 6)
	_place(_best_label, Control.PRESET_TOP_WIDE, 0, 278, 0, 320)

	var top_bar := HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	top_bar.add_theme_constant_override("separation", 12)
	_place(top_bar, Control.PRESET_TOP_WIDE, 20, 20, -20, 70)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(top_bar)
	_music_btn = _button(top_bar, "", 22, _toggle_music)
	_sfx_btn = _button(top_bar, "", 22, _toggle_sfx)

	var card := PanelContainer.new()
	_place(card, Control.PRESET_BOTTOM_WIDE, 36, -196, -36, -196)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var prev := _button(row, "◀", 34, func() -> void: _browse(-1))
	prev.custom_minimum_size = Vector2(80, 80)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", -6)
	row.add_child(name_box)
	_hero_title = _label(name_box, "", 30, Color("#7a2e12"))
	_hero_name = _label(name_box, "", 64, C_INK, true)
	var next := _button(row, "▶", 34, func() -> void: _browse(1))
	next.custom_minimum_size = Vector2(80, 80)
	_hero_desc = _label(v, "", 24, Color("#4a3423"))
	_hero_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_desc.custom_minimum_size = Vector2(560, 0)
	_hero_perk = _label(v, "", 26, Color("#9c2a1a"))
	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(coin_row)
	var icon := CoinIcon.new()
	icon.custom_minimum_size = Vector2(30, 30)
	coin_row.add_child(icon)
	_menu_coin_label = _label(coin_row, "", 26, Color("#4a3423"))
	_hero_btn = _button(v, "", 30, _on_hero_button)

	var start := _button(_menu, "开　跑", 64, func() -> void: start_pressed.emit(), true)
	_place(start, Control.PRESET_CENTER_BOTTOM, -190, -170, 190, -50)
	var help := _label(_menu, "↑ 跳跃　↓ 翻滚　← → 换道 / 路口转弯", 24, Color(C_PAPER, 0.85), false, 4)
	_place(help, Control.PRESET_BOTTOM_WIDE, 0, -46, 0, -10)


func _build_hud() -> void:
	_gradient_overlay(_hud, true, 200, 0.45)
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.05, 0.02, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_flash, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	_hud.add_child(_flash)

	_score_label = _label(_hud, "0", 64, Color.WHITE, true, 10)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_place(_score_label, Control.PRESET_TOP_LEFT, 28, 18, 400, 100)
	_dist_label = _label(_hud, "0 米", 28, C_PAPER, false, 6)
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_place(_dist_label, Control.PRESET_TOP_LEFT, 30, 96, 400, 136)

	var coin_box := HBoxContainer.new()
	coin_box.alignment = BoxContainer.ALIGNMENT_END
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(coin_box, Control.PRESET_TOP_RIGHT, -330, 30, -120, 90)
	_hud.add_child(coin_box)
	var icon := CoinIcon.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_box.add_child(icon)
	_coin_label = _label(coin_box, "0", 46, C_GOLD, true, 8)

	var pause := _button(_hud, "Ⅱ", 34, func() -> void: pause_pressed.emit())
	_place(pause, Control.PRESET_TOP_RIGHT, -100, 26, -24, 100)

	_power_box = VBoxContainer.new()
	_power_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_box.add_theme_constant_override("separation", 6)
	_place(_power_box, Control.PRESET_TOP_RIGHT, -260, 120, -24, 360)
	_hud.add_child(_power_box)
	for kind: String in POWER_NAMES:
		var r := VBoxContainer.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_constant_override("separation", 2)
		_power_box.add_child(r)
		var name_label := _label(r, POWER_NAMES[kind], 24, C_GOLD, false, 5)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 12)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(bar)
		r.visible = false
		_bars[kind] = bar
	_shield_row = _label(_power_box, "护心镜护体", 24, Color("#9fd3ff"), false, 5)
	_shield_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_toast = _label(_hud, "", 52, C_GOLD, true, 10, Color("#4a0c08"))
	_place(_toast, Control.PRESET_CENTER, -340, -260, 340, -170)
	_toast.pivot_offset = Vector2(340, 45)
	_toast.modulate.a = 0.0

	_banner = PanelContainer.new()
	_place(_banner, Control.PRESET_CENTER_TOP, -320, 170, 320, 330)
	_hud.add_child(_banner)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	_banner.add_child(bv)
	_banner_title = _label(bv, "", 80, C_INK, true)
	_banner_sub = _label(bv, "", 24, Color("#7a2e12"))
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint = _label(_hud, "↑ 跳跃　↓ 翻滚　← → 换道 / 路口转弯", 30, Color.WHITE, false, 8)
	_place(_hint, Control.PRESET_BOTTOM_WIDE, 0, -200, 0, -130)
	_hint.modulate.a = 0.0


func _modal(parent: Control) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = C_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_place(dim, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	parent.add_child(dim)
	var panel := PanelContainer.new()
	_place(panel, Control.PRESET_CENTER, -300, -330, 300, 330)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	return v


func _build_pause() -> void:
	var v := _modal(_pause)
	_label(v, "暂　停", 84, C_INK, true)
	_label(v, "好汉且歇口气", 28, Color("#4a3423"))
	_button(v, "继续奔逃", 36, func() -> void: resume_pressed.emit())
	_button(v, "重新开始", 36, func() -> void: restart_pressed.emit())
	_button(v, "返回主页", 36, func() -> void: home_pressed.emit())


func _build_over() -> void:
	var v := _modal(_over)
	_over_title = _label(v, "", 52, C_RED, true)
	_over_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_title.custom_minimum_size = Vector2(540, 0)
	_over_flavor = _label(v, "", 24, Color("#4a3423"))
	_over_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_flavor.custom_minimum_size = Vector2(540, 0)
	_over_record = _label(v, "新纪录！", 44, Color("#c0392b"), true, 6, Color(1, 1, 1, 0.8))
	_over_stats = _label(v, "", 32, C_INK)
	_revive_btn = _button(v, "", 32, func() -> void: revive_pressed.emit())
	_button(v, "再跑一次", 36, func() -> void: restart_pressed.emit())
	_button(v, "返回主页", 32, func() -> void: home_pressed.emit())


# ---------------------------------------------------------------- 主菜单逻辑

func _browse(step: int) -> void:
	_hero_idx = posmod(_hero_idx + step, GameState.HEROES.size())
	_refresh_menu()
	hero_previewed.emit(GameState.HEROES[_hero_idx]["id"])


func _on_hero_button() -> void:
	var h: Dictionary = GameState.HEROES[_hero_idx]
	if GameState.is_unlocked(h["id"]):
		GameState.select_hero(h["id"])
	elif GameState.try_unlock(h["id"]):
		Sfx.play("gong")
	_refresh_menu()


func _refresh_menu() -> void:
	if _best_label == null:
		return
	_best_label.text = "最高 %d 分　·　最远 %d 米" % [GameState.best_score, GameState.best_distance]
	_menu_coin_label.text = "　铜钱 %d" % GameState.total_coins
	var h: Dictionary = GameState.HEROES[_hero_idx]
	_hero_title.text = h["title"]
	_hero_name.text = h["name"]
	_hero_desc.text = h["desc"]
	_hero_perk.text = "特长：" + String(h["perk"])
	if GameState.is_unlocked(h["id"]):
		var selected: bool = GameState.selected_hero == h["id"]
		_hero_btn.text = "已出战" if selected else "派他出战"
		_hero_btn.disabled = selected
	else:
		_hero_btn.text = "解锁（%d 铜钱）" % h["cost"]
		_hero_btn.disabled = GameState.total_coins < int(h["cost"])
	_music_btn.text = "音乐：开" if GameState.music_on else "音乐：关"
	_sfx_btn.text = "音效：开" if GameState.sfx_on else "音效：关"


func _toggle_music() -> void:
	GameState.music_on = not GameState.music_on
	Sfx.set_music_enabled(GameState.music_on)
	GameState.save_game()
	_refresh_menu()


func _toggle_sfx() -> void:
	GameState.sfx_on = not GameState.sfx_on
	GameState.save_game()
	_refresh_menu()


## 铜钱图标：外圆内方。
class CoinIcon extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r, Color("#a8741f"))
		draw_circle(c, r * 0.84, Color("#e3b04b"))
		var h := r * 0.3
		draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), Color("#3a2510"))
