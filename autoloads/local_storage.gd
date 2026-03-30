extends Node

## Local note cache, per account. All note content is AES-encrypted via AccountManager.
##
## File layout:
##   user://cache/<account_id>/index.enc       — encrypted JSON {note_id_str: {v_hash, title, preview}}
##   user://cache/<account_id>/notes/<id>.enc  — encrypted JSON {_id, title, text}
##   user://cache/<account_id>/recent.json     — plaintext [note_id, ...] (last 10 opened)

const CACHE_BASE := "user://cache"

var _account_id: String = ""


func _ready() -> void:
	AccountManager.account_unlocked.connect(_on_account_unlocked)


func _on_account_unlocked(account_meta: Dictionary) -> void:
	_account_id = account_meta["id"]
	_ensure_dirs()


func is_ready() -> bool:
	return not _account_id.is_empty()


# ── Note index ────────────────────────────────────────────────────────────────

## Returns {note_id_str: {v_hash, title, preview}} from the encrypted local index.
func load_index() -> Dictionary:
	var data := _read_enc(_index_path())
	if data.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		return {}
	return json.get_data()


func save_index(index: Dictionary) -> void:
	_write_enc(_index_path(), JSON.stringify(index).to_utf8_buffer())


func get_local_hash(note_id: int) -> String:
	var index := load_index()
	var entry = index.get(str(note_id), {})
	return entry.get("v_hash", "")


# ── Individual notes ──────────────────────────────────────────────────────────

func has_note(note_id: int) -> bool:
	return FileAccess.file_exists(_note_path(note_id))


func get_note(note_id: int) -> Dictionary:
	var data := _read_enc(_note_path(note_id))
	if data.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		return {}
	return json.get_data()


func save_note(note: Dictionary) -> void:
	var note_id: int = note.get("_id", note.get("id", 0))
	_write_enc(_note_path(note_id), JSON.stringify(note).to_utf8_buffer())


# ── Sync info ─────────────────────────────────────────────────────────────────

func get_last_synced() -> int:
	return AccountManager.get_current_account().get("last_synced", 0)


func get_last_synced_string() -> String:
	var ts := get_last_synced()
	if ts == 0:
		return "Never"
	var diff := int(Time.get_unix_time_from_system()) - ts
	if diff < 60:
		return "Just now"
	elif diff < 3600:
		return "%d min ago" % (diff / 60)
	elif diff < 86400:
		return "%d h ago" % (diff / 3600)
	else:
		return "%d days ago" % (diff / 86400)


# ── Recently opened notes ─────────────────────────────────────────────────────

func get_recent_note_ids() -> Array:
	var path := "%s/%s/recent.json" % [CACHE_BASE, _account_id]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var json := JSON.new()
	var result := json.parse(f.get_as_text())
	f.close()
	if result != OK:
		return []
	var data = json.get_data()
	return data if data is Array else []


func add_to_recent(note_id: int) -> void:
	var recent := get_recent_note_ids()
	recent.erase(note_id)
	recent.insert(0, note_id)
	if recent.size() > 10:
		recent.resize(10)
	var path := "%s/%s/recent.json" % [CACHE_BASE, _account_id]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(recent))
		f.close()


# ── Cache management ──────────────────────────────────────────────────────────

## Deletes all cached files for the given account id.
func clear_account_cache(account_id: String) -> void:
	var base := "%s/%s" % [CACHE_BASE, account_id]
	_delete_dir_recursive(base)


# ── Private ───────────────────────────────────────────────────────────────────

func _index_path() -> String:
	return "%s/%s/index.enc" % [CACHE_BASE, _account_id]

func _note_path(note_id: int) -> String:
	return "%s/%s/notes/%d.enc" % [CACHE_BASE, _account_id, note_id]

func _ensure_dirs() -> void:
	var dir := DirAccess.open("user://")
	if not dir:
		return
	if not dir.dir_exists("cache"):
		dir.make_dir("cache")
	if not dir.dir_exists("cache/" + _account_id):
		dir.make_dir("cache/" + _account_id)
	if not dir.dir_exists("cache/" + _account_id + "/notes"):
		dir.make_dir("cache/" + _account_id + "/notes")

func _read_enc(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var raw := f.get_buffer(f.get_length())
	f.close()
	return AccountManager.decrypt_data(raw)

func _write_enc(path: String, data: PackedByteArray) -> void:
	var encrypted := AccountManager.encrypt_data(data)
	if encrypted.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(encrypted)
		f.close()


func _delete_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path + "/" + name
			if dir.current_is_dir():
				_delete_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
