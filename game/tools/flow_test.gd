extends Node
## End-to-end UI flow (headless): menu → quick match → results → menu → league match → results.
var step := 0
var t := 0.0
var log_lines := []

func _ready() -> void:
	if name != "FlowRunner":
		var r: Node = load("res://tools/flow_test.gd").new()
		r.name = "FlowRunner"
		get_tree().root.add_child.call_deferred(r)
		return
	Game.profile["created"] = true
	Game.profile["tutorial_done"] = true
	Game.profile["name"] = "Tester"
	Game.profile["league"] = {}
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _say(s: String) -> void:
	print("[flow] ", s)

func _process(delta: float) -> void:
	if name != "FlowRunner":
		return
	t += delta
	var cur := get_tree().current_scene
	if cur == null:
		return
	match step:
		0:
			if cur.name == "Menu" and t > 1.0:
				_say("menu ok → quick match")
				cur.call("_launch_quick")
				step = 1
				t = 0.0
		1:
			if cur is MatchView and t > 1.0:
				var mv := cur as MatchView
				_say("match loaded: %s vs %s, humans=%d" % [mv.cfg.team_names[0], mv.cfg.team_names[1], mv.cfg.humans.size()])
				mv.intro_t = 0.0
				mv.sim.clock = mv.sim.cfg.duration - 0.5
				step = 2
				t = 0.0
		2:
			if cur.name == "Results" and t > 0.5:
				_say("results ok: %s" % str(Game.last_result.get("score")))
				Game.goto("res://scenes/menu.tscn")
				step = 3
				t = 0.0
		3:
			if cur.name == "Menu" and t > 1.0:
				_say("menu → locker")
				Game.goto("res://scenes/locker.tscn")
				step = 4
				t = 0.0
		4:
			if cur.name == "Locker" and t > 1.5:
				cur.call("_show_tab", 2)
				cur.call("_show_tab", 6)
				_say("locker ok, tabs ok")
				Game.goto("res://scenes/menu.tscn")
				step = 5
				t = 0.0
		5:
			if cur.name == "Menu" and t > 1.0:
				_say("profile: level %d xp %d matches %d" % [int(Game.profile["level"]), int(Game.profile["xp"]), int(Game.profile["career"]["matches"])])
				_say("DONE")
				get_tree().quit()
	if t > 40.0:
		_say("TIMEOUT at step %d (scene %s)" % [step, cur.name])
		get_tree().quit()
