extends Node

## In-app debug log. Captures timestamped entries accessible from Settings → Debug Log.
## Also proxies to print() so the Godot console continues to work normally.

const MAX_ENTRIES := 500

var _entries: Array[Dictionary] = []


func log(message: String) -> void:
	print(message)
	_entries.append({
		"time": Time.get_time_string_from_system(),
		"msg":  message
	})
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()


func get_entries() -> Array[Dictionary]:
	return _entries


func clear() -> void:
	_entries.clear()
