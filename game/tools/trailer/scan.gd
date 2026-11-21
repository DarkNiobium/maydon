extends Node
## Headless: find trailer-worthy goals.
## godot --headless --path . res://tools/trailer/scan.tscn -- <kind> <seed0> <seed1>

const Cfg := preload("res://tools/trailer/cfg.gd")

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var kind := a[0]
	for seed in range(int(a[1]), int(a[2])):
		var m := MatchSim.new(Cfg.make(kind, seed))
		var kicks: Array = []     # recent kicks [{tick, id, team, kind, s, p}]
		while m.phase != MatchSim.Phase.FULLTIME and m.tick < 60 * 700:
			m.step()
			for e in m.events:
				var t: String = e["t"]
				if t == "kick":
					var p: Footballer = m.players[e["id"]]
					kicks.append({"tick": m.tick, "id": p.id, "team": p.team, "kind": str(e["kind"]), "s": float(e["s"]), "p": e["p"]})
					if kicks.size() > 40:
						kicks.pop_front()
				elif t == "goal" and not e.get("own", false):
					var sc := int(e["scorer"])
					var last: Dictionary = {}
					for k in range(kicks.size() - 1, -1, -1):
						if kicks[k]["id"] == sc:
							last = kicks[k]
							break
					if last.is_empty():
						continue
					var team := int(e["team"])
					var gx := m.pitch.goal_x(m.side_of(team))
					var kp: Vector3 = last["p"]
					var dist := Vector2(kp.x - gx, kp.z).length()
					# team passes in the 12 s before the shot (build-up)
					var passes := 0
					for k in kicks:
						if k["team"] == team and k["tick"] > last["tick"] - 720 and k["tick"] < last["tick"]:
							passes += 1
					print("GOAL kind=%s seed=%d tick=%d kick_tick=%d team=%d scorer=%d shot=%s speed=%.1f dist=%.1f h=%.2f passes=%d assist=%d score=%d-%d" % [
						kind, seed, m.tick, last["tick"], team, sc, last["kind"], last["s"], dist, kp.y, passes,
						int(e.get("assist", -1)), m.teams[0]["score"], m.teams[1]["score"]])
		print("DONE seed=%d ticks=%d" % [seed, m.tick])
	get_tree().quit()
