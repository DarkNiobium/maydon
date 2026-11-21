extends Node
## Headless server entry: `-- --mm port=47900` runs the matchmaker,
## `-- --match port=47910 spec=/path.json` runs one dedicated match.

func _ready() -> void:
	var args := {}
	var mode := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			mode = a.trim_prefix("--")
		elif a.contains("="):
			args[a.get_slice("=", 0)] = a.substr(a.find("=") + 1)
	Engine.max_fps = 60
	match mode:
		"mm":
			var mm := MatchmakerServer.new()
			add_child(mm)
			mm.start(args)
		"match":
			var spec := {}
			var f := FileAccess.open(str(args.get("spec", "")), FileAccess.READ)
			if f:
				var d = JSON.parse_string(f.get_as_text())
				if typeof(d) == TYPE_DICTIONARY:
					spec = d
			if spec.is_empty() or not Net.host_dedicated(int(args.get("port", 47910)), spec):
				print("[match] bad spec / port")
				get_tree().quit(1)
		_:
			print("usage: --mm port=47900 | --match port=N spec=FILE")
			get_tree().quit(1)
