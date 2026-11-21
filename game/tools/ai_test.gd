extends Node
func _ready() -> void:
	var img := Image.load_from_file(OS.get_cmdline_user_args()[0])
	var ai := AiFace.new()
	add_child(ai)
	ai.done.connect(func(ok: bool, data: Dictionary, err: String) -> void:
		print("AI ok=", ok, " err=", err)
		print(JSON.stringify(data).substr(0, 600))
		var l := Look.from_ai(data, Look.default_look())
		print("look hair=", l["hair"], " beard=", l["beard"], " tone=", l["skin_tone"])
		get_tree().quit())
	ai.analyze(img)
