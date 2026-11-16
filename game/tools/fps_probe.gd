extends SceneTree
var t := 0.0
var n := 0
func _initialize():
	var s = load("res://scenes/match.tscn").instantiate()
	root.add_child(s)
func _process(dt):
	t += dt
	n += 1
	if n % 30 == 0:
		print("frame ", n, " t=", snapped(t, 0.01), " fps=", Engine.get_frames_per_second())
	if t > 12.0:
		quit()
