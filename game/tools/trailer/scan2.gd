extends Node
## Headless: list saves, slide tackles, posts/bars. -- <kind> <seed0> <seed1>
const Cfg := preload("res://tools/trailer/cfg.gd")

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for seed in range(int(a[1]), int(a[2])):
		var m := MatchSim.new(Cfg.make(a[0], seed))
		var last_shot := {}
		while m.phase != MatchSim.Phase.FULLTIME and m.tick < 60 * 700:
			m.step()
			for e in m.events:
				var t: String = e["t"]
				if t == "kick" and str(e["kind"]) == "shot":
					last_shot = {"tick": m.tick, "s": float(e["s"]), "p": e["p"], "id": int(e["id"])}
				elif t == "save":
					var gk: Footballer = m.players[e["id"]]
					print("SAVE kind=%s seed=%d tick=%d gk=%d catch=%s shot_tick=%d shot_s=%.1f shooter=%d ball_h=%.2f" % [a[0], seed, m.tick, gk.id,
						str(e.get("catch", false)), int(last_shot.get("tick", -1)), float(last_shot.get("s", 0.0)), int(last_shot.get("id", -1)), m.ball.pos.y])
				elif t == "tackle" and e.get("slide", false) and e.get("won", false):
					print("SLIDE kind=%s seed=%d tick=%d id=%d" % [a[0], seed, m.tick, int(e["id"])])
				elif t == "post" or t == "bar":
					print("%s kind=%s seed=%d tick=%d" % [t.to_upper(), a[0], seed, m.tick])
	get_tree().quit()
