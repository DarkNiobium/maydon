extends Node
func _ready() -> void:
	var cfg := Game.quick_match(5, Footballer.Role.FWD, 1)
	Game.next_match = cfg
	Game.next_match_meta = {"mode": "quick"}
	var view: MatchView = load("res://scenes/match.tscn").instantiate()
	view.manual_step = true
	add_child(view)
	await get_tree().process_frame
	view.intro_t = 0.0
	view.advance(60)
	var cv: CharacterView = view.views[view.human_id]
	print("before emo_end ", cv._emo_end, " t ", cv._t)
	view.hud.emote_wheel.pick(0)
	for i in 10:
		view.advance(2, 1.0 / 30.0)
		await get_tree().process_frame
	print("after emo_end ", cv._emo_end, " t ", cv._t, " anim ", cv._emo_node.animation)
	get_tree().quit()
