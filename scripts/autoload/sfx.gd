extends Node
## 程序化音效与配乐（自动加载）。
## 不依赖任何音频素材：启动时用合成器生成短音效，
## 背景音乐（五声音阶的拨弦 + 战鼓）在后台线程里合成，完成后自动循环播放。

const RATE := 22050
const POOL_SIZE := 8
## 五声音阶（D 宫调）：D E F# A B，各音相对 D 的半音数。
const PENTATONIC := [0, 2, 4, 7, 9]

var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _music_task := -1
var _mbuf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)
	_build_sfx()
	if DisplayServer.get_name() != "headless":
		_music_task = WorkerThreadPool.add_task(_build_music, false, "bgm")


func _process(_delta: float) -> void:
	if _music_task >= 0 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		_music.stream = _music_stream
		set_music_enabled(GameState.music_on)


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
	for p in _pool:
		p.stop()
		p.stream = null
	_music.stop()
	_music.stream = null
	_sfx.clear()


func play(sfx_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not GameState.sfx_on or not _sfx.has(sfx_name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _sfx[sfx_name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func set_music_enabled(on: bool) -> void:
	if _music.stream == null:
		return
	if on and not _music.playing:
		_music.play()
	elif not on and _music.playing:
		_music.stop()


# ---------------------------------------------------------------- 合成工具

func _env(i: int, n: int, attack: float, curve := 3.0) -> float:
	var t := float(i) / RATE
	var a := minf(1.0, t / maxf(attack, 0.0001))
	return a * pow(1.0 - float(i) / n, curve)


func _sweep(f0: float, f1: float, dur: float, vol := 0.5, noise_mix := 0.0, curve := 3.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / RATE
		var s := sin(phase) * (1.0 - noise_mix) + _rng.randf_range(-1.0, 1.0) * noise_mix
		out[i] = s * vol * _env(i, n, 0.005, curve)
	return out


func _noise(dur: float, vol := 0.4, smooth := 0.5, curve := 2.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		last = lerpf(_rng.randf_range(-1.0, 1.0), last, smooth)
		out[i] = last * vol * _env(i, n, 0.02, curve)
	return out


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: PackedFloat32Array in parts:
		out.append_array(p)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _gong(f0: float, dur: float, vol: float) -> PackedFloat32Array:
	# 锣：一组非谐波泛音，缓慢衰减，音高略微下滑。
	var ratios := [1.0, 1.48, 2.06, 2.63, 3.41, 4.12]
	var amps := [1.0, 0.7, 0.55, 0.4, 0.3, 0.2]
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var bend := 1.0 - 0.04 * minf(1.0, t / dur)
		var s := 0.0
		for k in ratios.size():
			s += sin(TAU * f0 * ratios[k] * bend * t) * amps[k] * exp(-t * (1.2 + k * 0.6))
		out[i] = s * vol * minf(1.0, t / 0.004) * 0.35
	return out


func _drum(f0: float, dur: float, vol: float) -> PackedFloat32Array:
	# 战鼓：低频正弦快速降调 + 一点噪声的鼓皮声。
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * f0 * (1.0 + 1.5 * exp(-t * 30.0)) / RATE
		var body := sin(phase) * exp(-t * 7.0)
		var skin := _rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.4
		out[i] = (body + skin) * vol
	return out


func _build_sfx() -> void:
	_sfx["coin"] = _to_wav(_concat([_sweep(1320, 1320, 0.05, 0.28, 0.0, 1.0), _sweep(1980, 1980, 0.16, 0.3)]))
	_sfx["jump"] = _to_wav(_mix(_sweep(260, 620, 0.18, 0.3, 0.15), _noise(0.18, 0.12, 0.6)))
	_sfx["roll"] = _to_wav(_noise(0.3, 0.35, 0.85, 1.5))
	_sfx["turn"] = _to_wav(_mix(_noise(0.16, 0.3, 0.7), _sweep(500, 300, 0.12, 0.12)))
	_sfx["lane"] = _to_wav(_noise(0.09, 0.18, 0.5))
	_sfx["stumble"] = _to_wav(_mix(_drum(80, 0.3, 0.7), _noise(0.15, 0.25, 0.3)))
	_sfx["crash"] = _to_wav(_mix(_drum(55, 0.7, 0.9), _noise(0.5, 0.4, 0.4)))
	_sfx["fall"] = _to_wav(_sweep(900, 160, 0.8, 0.3, 0.05, 1.2))
	_sfx["click"] = _to_wav(_sweep(1100, 900, 0.05, 0.35, 0.0, 4.0))
	_sfx["gong"] = _to_wav(_gong(170.0, 2.2, 0.9))
	_sfx["drum"] = _to_wav(_drum(70, 0.5, 0.9))
	_sfx["shield"] = _to_wav(_mix(_gong(520.0, 0.6, 0.6), _noise(0.2, 0.2, 0.2)))
	var arp := []
	for k in 5:
		arp.append(_sweep(587.33 * pow(2.0, PENTATONIC[k] / 12.0), 587.33 * pow(2.0, PENTATONIC[k] / 12.0), 0.07, 0.25, 0.0, 1.5))
	_sfx["powerup"] = _to_wav(_concat(arp))


# ---------------------------------------------------------------- 背景音乐

func _note_freq(degree: int, base := 293.66) -> float:
	var octave := floori(float(degree) / 5.0)
	var step: int = PENTATONIC[posmod(degree, 5)]
	return base * pow(2.0, octave + step / 12.0)


func _pluck(start: int, freq: float, dur: float, amp: float, damp: float, rng: RandomNumberGenerator) -> void:
	# Karplus-Strong 拨弦，近似古筝 / 琵琶的音色；超出结尾的部分绕回开头，保证无缝循环。
	var period := maxi(2, int(RATE / freq))
	var ring := PackedFloat32Array()
	ring.resize(period)
	for i in period:
		ring[i] = rng.randf_range(-1.0, 1.0)
	var total := int(dur * RATE)
	var size := _mbuf.size()
	var idx := 0
	for t in total:
		var cur := ring[idx]
		var nxt_i := idx + 1
		if nxt_i == period:
			nxt_i = 0
		ring[idx] = (cur + ring[nxt_i]) * 0.5 * damp
		idx = nxt_i
		_mbuf[(start + t) % size] += cur * amp


func _hit(start: int, samples: PackedFloat32Array, amp: float) -> void:
	var size := _mbuf.size()
	for i in samples.size():
		_mbuf[(start + i) % size] += samples[i] * amp


func _build_music() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 108  # 一百单八将
	var beat := 0.6
	var bars := 8
	var eighth := int(beat * 0.5 * RATE)
	_mbuf.resize(int(beat * 4 * bars * RATE))
	_mbuf.fill(0.0)

	# 旋律：两小节动机 A，变奏 A'，对比 B，再回到 A。
	var motif: Array[int] = []
	var degree := 5
	for i in 16:
		if i % 4 == 3 and rng.randf() < 0.5:
			motif.append(-99)  # 休止
			continue
		degree = clampi(degree + rng.randi_range(-2, 2), 3, 9)
		motif.append(degree)
	var phrases: Array = [motif, motif.duplicate(), [], motif]
	for i in 16:
		var d: int = motif[i]
		phrases[1][i] = d if i < 12 or d == -99 else clampi(d + 1, 3, 10)
		phrases[2].append(-99 if d == -99 else clampi(10 - d + 2, 3, 10))
	var pos := 0
	for phrase: Array in phrases:
		for d: int in phrase:
			if d != -99:
				_pluck(pos, _note_freq(d), 0.9, 0.32, 0.996, rng)
			pos += eighth

	# 低音：每小节一、三拍。
	var bass_line := [0, 0, -2, -1, 0, 0, -3, -1]
	for bar in bars:
		var root: int = bass_line[bar]
		_pluck(bar * eighth * 8, _note_freq(root, 73.42), 1.4, 0.45, 0.998, rng)
		_pluck(bar * eighth * 8 + eighth * 4, _note_freq(root + 3, 73.42), 1.2, 0.35, 0.998, rng)

	# 战鼓与梆子。
	var drum := _drum(62, 0.45, 1.0)
	var wood := _sweep(1250, 1100, 0.04, 0.5, 0.0, 4.0)
	for b in bars * 4:
		var start := b * eighth * 2
		if b % 2 == 0:
			_hit(start, drum, 0.55 if b % 8 == 0 else 0.35)
		else:
			_hit(start + eighth, wood, 0.18)

	var peak := 0.01
	for v in _mbuf:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak
	for i in _mbuf.size():
		_mbuf[i] *= gain
	_music_stream = _to_wav(_mbuf, true)
