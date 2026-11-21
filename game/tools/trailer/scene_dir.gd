extends Node
## Trailer: capture a UI scene (locker / lobby) with timed actions, same frame + audio pipeline as director.gd.
##   ... res://tools/trailer/scene_dir.tscn -- <shot> <out_dir>

const FPS := 30.0
const WARM := 45

const SHOTS := {
	"s12_locker": {"scene": "res://scenes/locker.tscn", "len": 3.5555556, "actions": [
		[0.0, "look", 21, "hair_short_fade", 5], [0.0, "sway", 0.42],
		[0.889, "look", 34, "hair_side_part", 2], [0.889, "tab", 1],
		[1.778, "look", 7, "hair_man_bun", 1], [1.778, "tab", 2],
		[2.667, "look", 52, "hair_crop", 5], [2.667, "tab", 5]]},
	"s13_lobby": {"scene": "res://scenes/menu.tscn", "len": 3.5555556, "actions": [
		[0.0, "call", "demo_room"],
		[0.6, "mate_emote", 0, "emote_wave"], [0.9, "emote", "emote_flex"], [1.2, "mate_emote", 1, "clap"],
		[2.667, "call", "demo_versus"]]},
}

var spec: Dictionary
var node: Node
var f := -WARM
var total := 0
var out_dir := ""
var _cur := -999
var _tasks: Array = []
var _p0 := -1
var _done: Dictionary = {}
var _yaw_speed := 0.0
var _sway := 0.0
var _save_backup: PackedByteArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	spec = SHOTS[args[0]]
	out_dir = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.frame_post_draw.connect(_grab)
	var want := DisplayServer.screen_get_size()
	if get_window().size != want:
		get_window().size = want
	total = int(round(float(spec["len"]) * FPS))
	# the demo profile must never reach the player's real save file
	if FileAccess.file_exists(Game.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_bytes(Game.SAVE_PATH)
	Game.profile["created"] = true
	Game.profile["name"] = "Karimov"
	Game.profile["level"] = 7
	Game.profile["coins"] = 1240
	Game.settings["quality"] = 2
	node = load(spec["scene"]).instantiate()
	add_child(node)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	print("[scene] %s frames=%d" % [args[0], total])


func _grab() -> void:
	if _cur < 0 or _cur >= total:
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/f_%04d.png" % [out_dir, _cur]
	_tasks.append(WorkerThreadPool.add_task(func() -> void: img.save_png(path)))
	_cur = -999


func _look(seed: int, hair: String, tab: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var l := Look.random_look(r)
	l["hair"] = hair
	node.set("look", l)
	node.call("_rebuild_model")
	if tab >= 0:
		node.call("_show_tab", tab)


func _process(_d: float) -> void:
	var i := f + WARM
	if f >= total:
		for id: int in _tasks:
			WorkerThreadPool.wait_for_task_completion(id)
		print("[director] done frames=%d p0=%d pend=%d" % [total, _p0, Engine.get_process_frames()])
		if not _save_backup.is_empty() and FileAccess.get_file_as_bytes(Game.SAVE_PATH) != _save_backup:
			var fw := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
			fw.store_buffer(_save_backup)
			fw.close()
			print("[scene] restored save file")
		get_tree().quit()
		return
	if f == 0:
		_p0 = Engine.get_process_frames()
	while _tasks.size() > 12:
		WorkerThreadPool.wait_for_task_completion(_tasks.pop_front())
	# actions fire during warm-up when their time is 0 (so the first frame is settled)
	var t := float(f) / FPS
	for k in spec["actions"].size():
		var a: Array = spec["actions"][k]
		var at := float(a[0])
		var fire_t := at if at > 0.0 else -float(WARM - 5) / FPS
		if _done.has(k) or t < fire_t:
			continue
		_done[k] = true
		match str(a[1]):
			"look":
				_look(int(a[2]), str(a[3]), int(a[4]))
			"tab":
				node.call("_show_tab", int(a[2]))
			"yaw":
				_yaw_speed = float(a[2])
			"sway":
				_sway = float(a[2])
			"call":
				node.call(str(a[2]))
			"emote":
				(node.get("lobby") as Node).call("play_emote", str(a[2]))
			"mate_emote":
				(node.get("lobby") as Node).call("play_mate_emote", int(a[2]), str(a[3]))
	if _sway != 0.0 and node.get("_yaw") != null:
		node.set("_yaw", 0.25 + _sway * sin(t * TAU / 4.5))
	if _yaw_speed != 0.0 and node.get("_yaw") != null:
		node.set("_yaw", float(node.get("_yaw")) + _yaw_speed / FPS)
	_cur = f
	f += 1
