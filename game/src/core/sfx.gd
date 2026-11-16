extends Node
## Audio: pooled one-shots by category, crowd loops that swell with danger,
## menu music. Files are discovered under res://assets/audio/<category>/.

const CATS := ["kick_soft", "kick_hard", "touch", "bounce", "post", "net", "wall",
	"whistle_short", "whistle_long", "whistle_end", "crowd_loop", "crowd_big", "crowd_goal",
	"crowd_ooh", "crowd_groan", "crowd_applause", "grunt", "tackle", "ui_click", "ui_ok", "ui_back", "music"]

var lib := {}
var pool: Array[AudioStreamPlayer] = []
var crowd_a: AudioStreamPlayer
var crowd_b: AudioStreamPlayer
var music: AudioStreamPlayer
var _crowd_target := 0.0
var _crowd_level := 0.0
var _in_match := false
var _last_touch := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		pool.append(p)
	crowd_a = AudioStreamPlayer.new()
	crowd_b = AudioStreamPlayer.new()
	music = AudioStreamPlayer.new()
	add_child(crowd_a)
	add_child(crowd_b)
	add_child(music)


func _scan() -> void:
	for c in CATS:
		lib[c] = []
	var base := "res://assets/audio/"
	var dir := DirAccess.open(base)
	if dir == null:
		return
	for c in CATS:
		var d2 := DirAccess.open(base + c)
		if d2 == null:
			continue
		for f in d2.get_files():
			var fn := f.trim_suffix(".import").trim_suffix(".remap")
			if fn.ends_with(".ogg") or fn.ends_with(".wav") or fn.ends_with(".mp3"):
				var path: String = base + c + "/" + fn
				if not lib[c].has(path):
					lib[c].append(path)


func _vol() -> float:
	return float(Game.settings.get("sfx", 0.9))


func play(cat: String, vol := 1.0, pitch := 1.0) -> void:
	var arr: Array = lib.get(cat, [])
	if arr.is_empty() or _vol() <= 0.01:
		return
	var path: String = arr[randi() % arr.size()]
	var s := load(path) as AudioStream
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.volume_db = linear_to_db(clampf(vol * _vol(), 0.001, 2.0))
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func _free_player() -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return pool[randi() % pool.size()]


func _process(delta: float) -> void:
	if not _in_match:
		return
	_crowd_level = move_toward(_crowd_level, _crowd_target, delta * 0.6)
	var v := _vol()
	if crowd_a.stream:
		crowd_a.volume_db = linear_to_db(maxf(0.0001, (0.55 - _crowd_level * 0.15) * v))
	if crowd_b.stream:
		crowd_b.volume_db = linear_to_db(maxf(0.0001, _crowd_level * 0.8 * v))


func match_start(cfg: MatchConfig) -> void:
	_in_match = true
	stop_music()
	var big := cfg.per_side >= 9
	_start_loop(crowd_a, "crowd_loop" if not big else "crowd_big")
	_start_loop(crowd_b, "crowd_big" if not big else "crowd_loop")
	if not big:
		crowd_b.pitch_scale = 1.05


func match_end() -> void:
	_in_match = false
	crowd_a.stop()
	crowd_b.stop()


func _start_loop(p: AudioStreamPlayer, cat: String) -> void:
	var arr: Array = lib.get(cat, [])
	if arr.is_empty():
		p.stream = null
		return
	var s := load(arr[randi() % arr.size()]) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	p.volume_db = -80.0
	p.play(randf() * 5.0)


func crowd_level(v: float) -> void:
	_crowd_target = clampf(v, 0.0, 1.0)


func kick(speed: float, kind: String) -> void:
	if speed > 18.0 or kind == "shot":
		play("kick_hard", clampf(speed / 30.0, 0.5, 1.0))
	else:
		play("kick_soft", clampf(0.35 + speed / 25.0, 0.35, 0.9))


func touch(v: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t - _last_touch < 0.08:
		return
	_last_touch = t
	if lib["touch"].is_empty():
		play("kick_soft", v * 0.35, 1.2)
	else:
		play("touch", v * 0.6)


func bounce(s: float) -> void:
	if s > 1.5:
		play("bounce", clampf(s / 10.0, 0.15, 0.7))


func post(s: float) -> void:
	play("post", clampf(s / 20.0, 0.5, 1.0))
	crowd_ooh()


func net(s: float) -> void:
	play("net", clampf(s / 15.0, 0.3, 0.9))


func wall(s: float) -> void:
	if lib["wall"].is_empty():
		play("bounce", clampf(s / 12.0, 0.2, 0.8), 0.8)
	else:
		play("wall", clampf(s / 15.0, 0.2, 0.9))


func whistle(kind: String) -> void:
	match kind:
		"full":
			play("whistle_end", 0.8)
		"half":
			play("whistle_long", 0.8)
		"foul", "penalty", "offside":
			play("whistle_short", 0.8)
		_:
			play("whistle_short", 0.55)


func goal(cheer: bool) -> void:
	if cheer:
		play("crowd_goal", 1.0)
	else:
		play("crowd_groan", 0.8)
		play("crowd_goal", 0.45)


func crowd_ooh() -> void:
	play("crowd_ooh", 0.8)


func tackle() -> void:
	play("tackle", 0.6)


func grunt() -> void:
	play("grunt", 0.5)


func ui(kind := "click") -> void:
	play("ui_" + kind, 0.6)


func play_music() -> void:
	var arr: Array = lib.get("music", [])
	if arr.is_empty() or music.playing:
		return
	var s := load(arr[randi() % arr.size()]) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	music.stream = s
	music.volume_db = linear_to_db(maxf(0.0001, float(Game.settings.get("music", 0.55)) * 0.6))
	music.play()


func stop_music() -> void:
	music.stop()


func set_music_volume(v: float) -> void:
	music.volume_db = linear_to_db(maxf(0.0001, v * 0.6))
