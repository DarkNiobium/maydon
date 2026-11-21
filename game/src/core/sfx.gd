extends Node
## Audio: pooled one-shots by category, crowd loops that swell with danger,
## menu music. Files are discovered under res://assets/audio/<category>/.

const CATS := ["kick_soft", "kick_hard", "touch", "bounce", "post", "net", "wall",
	"whistle_short", "whistle_long", "whistle_end", "crowd_loop", "crowd_big", "crowd_goal",
	"crowd_ooh", "crowd_groan", "crowd_applause", "grunt", "tackle", "ui_click", "ui_ok", "ui_back", "music", "footstep",
	"amb_day", "amb_night", "voice_goal", "voice_ooh", "voice_call"]

var lib := {}
var pool: Array[AudioStreamPlayer] = []
var pool3d: Array[AudioStreamPlayer3D] = []   # positional: heard from where it happens (camera = listener)
var crowd_a: AudioStreamPlayer
var crowd_b: AudioStreamPlayer
var music: AudioStreamPlayer
var _crowd_target := 0.0
var _crowd_level := 0.0
var _in_match := false
var _arena := false        # 3v3 / 5v5 cage: no stands, no crowd — city ambience, players' voices, music
var _last_touch := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		pool.append(p)
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 9.0           # full level within ~9 m, then 1/d
		p3.max_distance = 140.0
		p3.max_db = 3.0
		p3.panning_strength = 0.6
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p3)
		pool3d.append(p3)
	# never clip when many hits overlap (kicks + fence + voices)
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, lim)
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
	return float(Game.settings.get("sfx", 0.0))


func play(cat: String, vol := 1.0, pitch := 1.0, at = null) -> void:
	var arr: Array = lib.get(cat, [])
	if arr.is_empty() or _vol() <= 0.01:
		return
	var path: String = arr[randi() % arr.size()]
	var s := load(path) as AudioStream
	if s == null:
		return
	if at is Vector3 and is_inside_tree() and get_viewport().get_camera_3d() != null:
		var p3 := _free_player3d()
		p3.stream = s
		p3.global_position = at
		p3.volume_db = linear_to_db(clampf(vol * _vol(), 0.001, 1.0))
		p3.pitch_scale = pitch * randf_range(0.95, 1.05)
		p3.play()
		return
	var p := _free_player()
	p.stream = s
	p.volume_db = linear_to_db(clampf(vol * _vol(), 0.001, 1.0))
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func _free_player3d() -> AudioStreamPlayer3D:
	for p in pool3d:
		if not p.playing:
			return p
	return pool3d[randi() % pool3d.size()]


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
	if _arena:
		if crowd_a.stream:
			crowd_a.volume_db = linear_to_db(maxf(0.0001, 0.32 * v))    # ambience bed
		return
	if crowd_a.stream:
		crowd_a.volume_db = linear_to_db(maxf(0.0001, (0.55 - _crowd_level * 0.15) * v))
	if crowd_b.stream:
		crowd_b.volume_db = linear_to_db(maxf(0.0001, _crowd_level * 0.8 * v))


func match_start(cfg: MatchConfig) -> void:
	_in_match = true
	stop_music()
	var big := cfg.per_side >= 9
	_arena = not big
	crowd_b.stop()
	crowd_b.stream = null
	if _arena:
		# small-sided game in a city cage: nobody in the stands, so no stadium crowd — the street
		# around, the ball, the fence, the players; an in-game track under it (music volume setting)
		_start_loop(crowd_a, "amb_night" if cfg.night else "amb_day")
		_crowd_level = 0.0
		var arr: Array = lib.get("music", [])
		if not arr.is_empty():
			var ms := load(arr[randi() % arr.size()]) as AudioStream
			if ms is AudioStreamOggVorbis:
				(ms as AudioStreamOggVorbis).loop = true
			music.stream = ms
			music.volume_db = linear_to_db(maxf(0.0001, float(Game.settings.get("music", 0.0)) * 0.28))
			music.play()
		return
	_start_loop(crowd_a, "crowd_loop" if not big else "crowd_big")
	_start_loop(crowd_b, "crowd_big" if not big else "crowd_loop")
	if not big:
		crowd_b.pitch_scale = 1.05


func match_end() -> void:
	_in_match = false
	crowd_a.stop()
	crowd_b.stop()
	if _arena:
		music.stop()
	_arena = false


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


func kick(speed: float, kind: String, at = null) -> void:
	if speed > 18.0 or kind == "shot":
		play("kick_hard", clampf(speed / 32.0, 0.55, 0.95), 1.0, at)
	else:
		play("kick_soft", clampf(0.3 + speed / 30.0, 0.3, 0.75), 1.0, at)


func touch(v: float, at = null) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t - _last_touch < 0.08:
		return
	_last_touch = t
	if lib["touch"].is_empty():
		play("kick_soft", v * 0.3, 1.2, at)
	else:
		play("touch", clampf(v * 0.9, 0.1, 0.8), 1.0, at)


func bounce(s: float, at = null) -> void:
	if s > 1.5:
		play("bounce", clampf(s / 12.0, 0.15, 0.6), 1.0, at)


func post(s: float, at = null) -> void:
	play("post", clampf(s / 20.0, 0.5, 1.0), 1.0, at)
	crowd_ooh(at)


func net(s: float, at = null) -> void:
	play("net", clampf(s / 15.0, 0.3, 0.85), 1.0, at)


func wall(s: float, at = null) -> void:
	if lib["wall"].is_empty():
		play("bounce", clampf(s / 12.0, 0.2, 0.7), 0.8, at)
	else:
		play("wall", clampf(s / 14.0, 0.25, 0.9), 1.0, at)


func whistle(kind: String) -> void:
	if _arena:
		# no referee in a cage game: only the start / end signal, softer
		if kind in ["full", "half"]:
			play("whistle_long" if kind == "half" else "whistle_end", 0.45)
		elif kind == "kickoff":
			play("whistle_short", 0.35)
		return
	match kind:
		"full":
			play("whistle_end", 0.8)
		"half":
			play("whistle_long", 0.8)
		"foul", "penalty", "offside":
			play("whistle_short", 0.8)
		_:
			play("whistle_short", 0.55)


func goal(cheer: bool, at = null) -> void:
	if _arena:
		play("voice_goal", 0.85, 1.0, at)          # the scorers shout, nobody else is there
		return
	if cheer:
		play("crowd_goal", 1.0)
	else:
		play("crowd_groan", 0.8)
		play("crowd_goal", 0.45)


func crowd_ooh(at = null) -> void:
	if _arena:
		play("voice_ooh", 0.7, 1.0, at)
		return
	play("crowd_ooh", 0.8)


## A player calls for the ball (human "call" button, through-run request).
func call_for_ball(at = null) -> void:
	play("voice_call", 0.6, 1.0, at)


func tackle() -> void:
	play("tackle", 0.6)


func grunt(at = null) -> void:
	play("grunt", 0.4, 1.0, at)


func footstep(v: float) -> void:
	play("footstep", v * 0.5)


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
	music.volume_db = linear_to_db(maxf(0.0001, float(Game.settings.get("music", 0.0)) * 0.6))
	music.play()


func stop_music() -> void:
	music.stop()


func set_music_volume(v: float) -> void:
	music.volume_db = linear_to_db(maxf(0.0001, v * (0.28 if _in_match and _arena else 0.6)))
