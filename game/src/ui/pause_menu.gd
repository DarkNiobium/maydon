class_name PauseMenu
extends RefCounted
## Pause overlay for the match scene.

static var _layer: CanvasLayer


static func toggle(view: MatchView, on: bool) -> void:
	if _layer and is_instance_valid(_layer):
		_layer.queue_free()
		_layer = null
	if not on:
		view.get_tree().paused = false
		return
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	view.add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -200)
	box.custom_minimum_size = Vector2(440, 400)
	box.add_theme_constant_override("separation", 18)
	_layer.add_child(box)
	var title := Label.new()
	title.text = "PAUZA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://assets/fonts/Oswald.ttf"))
	title.add_theme_font_size_override("font_size", 72)
	box.add_child(title)
	var mk := func(txt: String, cb: Callable) -> void:
		var b := UiKit.big_button(txt)
		b.pressed.connect(cb)
		box.add_child(b)
	mk.call("DAVOM ETISH", func() -> void: view._toggle_pause())
	mk.call("KAMERA: " + ("ORQADAN" if view.cam.mode == CameraRig.Mode.PRO else "TELEVIZOR"), func() -> void:
		view.cam.mode = CameraRig.Mode.TV if view.cam.mode == CameraRig.Mode.PRO else CameraRig.Mode.PRO
		Game.settings["camera"] = 1 if view.cam.mode == CameraRig.Mode.TV else 0
		Game.save_game()
		view.cam.snap()
		view._toggle_pause())
	mk.call("CHIQISH", func() -> void:
		view.get_tree().paused = false
		Sfx.match_end()
		Game.goto("res://scenes/menu.tscn"))
