extends Node
## Lobby PLAY without a server: local search → versus → match vs bots.
var t := 0.0
var pressed := false
func _ready() -> void:
	var tree := get_tree()
	Game.settings["server"] = ""
	(func() -> void:
		var r := tree.root
		get_parent().remove_child(self)
		r.add_child(self)
		tree.change_scene_to_file("res://scenes/menu.tscn")).call_deferred()

func _process(delta: float) -> void:
	t += delta
	var sc := get_tree().current_scene
	if sc and sc.name == "Menu" and t > 2.0 and not pressed:
		pressed = true
		sc.call("_on_play")
		print("[play] pressed, searching=", Net.party.searching)
	if sc and sc.name == "Match":
		var mv := sc as MatchView
		print("[play] match loaded at %.1fs, per side %d, human %d" % [t, mv.cfg.per_side, mv.human_id])
		get_tree().quit()
	if t > 25.0:
		print("[play] timeout, scene ", sc.name if sc else "none")
		get_tree().quit()
