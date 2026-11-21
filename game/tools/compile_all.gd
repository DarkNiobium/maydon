extends Node
## Loads every script/scene under res://src and res://scenes to surface parse errors.
func _ready() -> void:
	var n := 0
	for dir in ["res://src", "res://scenes"]:
		n += _walk(dir)
	print("compiled ", n, " files")
	get_tree().quit()

func _walk(path: String) -> int:
	var c := 0
	var d := DirAccess.open(path)
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			var r = load(path + "/" + f)
			if r == null:
				print("FAILED ", path + "/" + f)
			c += 1
	for sd in d.get_directories():
		c += _walk(path + "/" + sd)
	return c
