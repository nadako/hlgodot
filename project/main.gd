extends Node

func _ready():
	var gdn = GDNative.new()
	gdn.library = load("res://hlgodot_entry.gdnlib")
	gdn.initialize()
	#gdn.terminate()
